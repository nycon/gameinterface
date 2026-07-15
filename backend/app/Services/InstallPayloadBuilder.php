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
        }

        return $allocation;
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
        $payload['minecraft_version'] = data_get($def, 'variables', []);
        if (is_array($payload['minecraft_version'])) {
            $ver = 'latest';
            foreach ($payload['minecraft_version'] as $variable) {
                if (($variable['env'] ?? '') === 'MINECRAFT_VERSION') {
                    $ver = (string) ($variable['default'] ?? 'latest');
                    break;
                }
                if (($variable['env'] ?? '') === 'MEMORY_MIN') {
                    $payload['memory_min'] = (string) ($variable['default'] ?? $payload['memory_min']);
                }
                if (($variable['env'] ?? '') === 'MEMORY_MAX' && empty($payload['memory_max'])) {
                    $payload['memory_max'] = (string) ($variable['default'] ?? '2048M');
                }
            }
            $payload['minecraft_version'] = $ver;
        }

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
