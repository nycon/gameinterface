<?php

namespace App\Services;

use App\Models\Allocation;
use App\Models\ImageVersion;
use App\Models\Server;
use Symfony\Component\Yaml\Yaml;

class InstallPayloadBuilder
{
    public function for(Server $server, array $extra = []): array
    {
        $server->loadMissing(['template', 'imageVersion.image', 'allocations']);

        $payload = [
            'server_id' => $server->id,
            'server_uuid' => $server->uuid,
            'linux_user' => $server->linux_user ?: ('gp-s'.$server->id),
            'install_path' => $server->install_path ?: ('/srv/gamepanel/servers/'.$server->uuid),
            'startup_command' => $server->startup_command,
            'memory_max' => $server->memory_max ?: '2048M',
            'memory_min' => '1024M',
            'cpu_percent' => $this->cpuPercent($server->cpu_quota),
        ];

        if ($server->template) {
            $payload['steam_app_id'] = $server->template->steam_app_id ?: '';
            $payload['template_slug'] = $server->template->slug;
            $this->applyTemplateYaml($payload, (string) $server->template->yaml_definition);
        }

        $version = $server->imageVersion;
        if (! $version && ! empty($extra['image_version_id'])) {
            $version = ImageVersion::query()->with('image')->find($extra['image_version_id']);
        }
        if ($version) {
            $payload['image_version_id'] = $version->id;
            $payload['archive_remote'] = $version->archive_path ?: $version->archive_name;
            $payload['manifest_remote'] = $version->manifest_path;
            $payload['archive_path'] = $version->archive_path;
        }

        $allocation = $server->allocations->first();
        if ($allocation) {
            $payload['port'] = $allocation->port;
            $payload['protocol'] = $allocation->protocol ?: 'tcp';
        }

        return array_merge($payload, $extra);
    }

    public function claimAllocation(Server $server): ?Allocation
    {
        if ($server->allocations()->exists()) {
            return $server->allocations()->first();
        }

        $allocation = Allocation::query()
            ->where('node_id', $server->node_id)
            ->whereNull('server_id')
            ->orderBy('port')
            ->first();

        if ($allocation) {
            $allocation->update(['server_id' => $server->id]);

            return $allocation;
        }

        return $this->createNextAllocation($server);
    }

    public function createNextAllocation(Server $server): ?Allocation
    {
        $server->loadMissing(['template', 'node']);
        if (! $server->node) {
            return null;
        }

        [$defaultPort, $protocol] = $this->defaultPortFromTemplate($server);
        $used = Allocation::query()
            ->where('node_id', $server->node_id)
            ->pluck('port')
            ->all();
        $usedLookup = array_fill_keys($used, true);

        $port = $defaultPort;
        while (isset($usedLookup[$port]) && $port < 65535) {
            $port++;
        }

        return Allocation::query()->create([
            'node_id' => $server->node_id,
            'server_id' => $server->id,
            'ip' => $server->node->ip_address,
            'port' => $port,
            'protocol' => $protocol,
            'notes' => 'auto',
        ]);
    }

    /**
     * Legt einen Start-Pool an Ports an (Minecraft u.a.), damit Install ohne manuellen Port klappt.
     */
    public function seedNodeAllocations(\App\Models\Node $node, int $count = 50, int $startPort = 25565): void
    {
        $existing = Allocation::query()->where('node_id', $node->id)->pluck('port')->all();
        $lookup = array_fill_keys($existing, true);
        $port = $startPort;
        $created = 0;

        while ($created < $count && $port <= 65535) {
            if (! isset($lookup[$port])) {
                Allocation::query()->create([
                    'node_id' => $node->id,
                    'server_id' => null,
                    'ip' => $node->ip_address,
                    'port' => $port,
                    'protocol' => 'tcp',
                    'notes' => 'pool',
                ]);
                $created++;
            }
            $port++;
        }
    }

    /** @return array{0:int,1:string} */
    private function defaultPortFromTemplate(Server $server): array
    {
        $defaultPort = 25565;
        $protocol = 'tcp';
        $yaml = (string) ($server->template?->yaml_definition ?? '');
        if ($yaml === '') {
            return [$defaultPort, $protocol];
        }
        try {
            $def = Yaml::parse($yaml);
            $ports = data_get($def, 'ports', []);
            if (is_array($ports) && isset($ports[0]) && is_array($ports[0])) {
                $defaultPort = (int) ($ports[0]['default'] ?? $defaultPort);
                $protocol = (string) ($ports[0]['protocol'] ?? 'tcp');
            }
        } catch (\Throwable) {
            // keep defaults
        }

        return [max(1, min(65535, $defaultPort)), in_array($protocol, ['tcp', 'udp'], true) ? $protocol : 'tcp'];
    }

    private function applyTemplateYaml(array &$payload, string $yaml): void
    {
        if ($yaml === '') {
            return;
        }

        try {
            $def = Yaml::parse($yaml);
        } catch (\Throwable) {
            if (! $payload['startup_command'] && preg_match('/startup:\s*\n\s*command:\s*"?([^"\n]+)"?/m', $yaml, $m)) {
                $payload['startup_command'] = trim($m[1]);
            }

            return;
        }

        if (! is_array($def)) {
            return;
        }

        $payload['install_strategy'] = data_get($def, 'image.strategy', data_get($def, 'type', ''));
        $payload['work_dir'] = data_get($def, 'runtime.work_dir', '/server');

        $vars = data_get($def, 'variables', []);
        $ver = 'latest';
        $motd = 'GamePanel Minecraft Server';
        $maxPlayers = '20';
        $onlineMode = 'true';
        if (is_array($vars)) {
            foreach ($vars as $variable) {
                if (! is_array($variable)) {
                    continue;
                }
                $env = (string) ($variable['env'] ?? '');
                $default = (string) ($variable['default'] ?? '');
                match ($env) {
                    'MINECRAFT_VERSION' => $ver = $default !== '' ? $default : $ver,
                    'MEMORY_MIN' => $payload['memory_min'] = $default !== '' ? $default : ($payload['memory_min'] ?? '1024M'),
                    'MEMORY_MAX' => $payload['memory_max'] = $payload['memory_max'] ?: ($default !== '' ? $default : '2048M'),
                    'MOTD' => $motd = $default !== '' ? $default : $motd,
                    'MAX_PLAYERS' => $maxPlayers = $default !== '' ? $default : $maxPlayers,
                    'ONLINE_MODE' => $onlineMode = $default !== '' ? $default : $onlineMode,
                    default => null,
                };
            }
        }
        $payload['minecraft_version'] = $ver;
        $payload['motd'] = $motd;
        $payload['max_players'] = $maxPlayers;
        $payload['online_mode'] = $onlineMode;

        if (empty($payload['startup_command'])) {
            $executable = data_get($def, 'runtime.executable');
            $args = data_get($def, 'runtime.args', []);
            if (is_string($executable)) {
                $parts = [$executable];
                if (is_array($args)) {
                    foreach ($args as $arg) {
                        $arg = str_replace(
                            ['{{MEMORY_MIN}}', '{{MEMORY_MAX}}'],
                            [$payload['memory_min'] ?? '1024M', $payload['memory_max'] ?? '2048M'],
                            (string) $arg
                        );
                        $parts[] = $arg;
                    }
                }
                $payload['startup_command'] = implode(' ', $parts);
            }
        }
    }

    private function cpuPercent(?string $quota): int
    {
        if (! $quota) {
            return 100;
        }
        if (preg_match('/(\d+)/', $quota, $m)) {
            return max(1, min(400, (int) $m[1]));
        }

        return 100;
    }
}
