<?php

namespace App\Services;

use App\Models\Allocation;
use App\Models\ImageVersion;
use App\Models\Server;

class InstallPayloadBuilder
{
    public function for(Server $server, array $extra = []): array
    {
        $server->loadMissing(['template', 'imageVersion.image', 'allocations']);

        $payload = [
            'server_id' => $server->id,
            'server_uuid' => $server->uuid,
            'linux_user' => $server->linux_user,
            'install_path' => $server->install_path,
            'startup_command' => $server->startup_command,
            'memory_max' => $server->memory_max,
            'cpu_percent' => $this->cpuPercent($server->cpu_quota),
        ];

        if ($server->template) {
            $payload['steam_app_id'] = $server->template->steam_app_id;
            if (! $payload['startup_command'] && filled($server->template->yaml_definition)) {
                if (preg_match('/startup:\s*\n\s*command:\s*"?([^"\n]+)"?/m', $server->template->yaml_definition, $m)) {
                    $payload['startup_command'] = trim($m[1]);
                }
            }
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
            $payload['protocol'] = $allocation->protocol ?: 'udp';
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
