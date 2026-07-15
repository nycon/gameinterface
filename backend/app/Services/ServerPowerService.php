<?php

namespace App\Services;

use App\Models\PanelJob;
use App\Models\Server;
use InvalidArgumentException;

class ServerPowerService
{
    private const ACTIONS = ['start', 'stop', 'restart', 'kill', 'install', 'update', 'backup', 'restore'];

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly InstallPayloadBuilder $installPayload,
    ) {}

    public function dispatch(Server $server, string $action, array $payload = []): PanelJob
    {
        if (! in_array($action, self::ACTIONS, true)) {
            throw new InvalidArgumentException("Invalid power action: {$action}");
        }

        $base = [
            'server_id' => $server->id,
            'server_uuid' => $server->uuid,
            'linux_user' => $server->linux_user,
            'install_path' => $server->install_path,
            'action' => $action,
        ];

        if (in_array($action, ['install', 'update'], true)) {
            $base = array_merge($this->installPayload->for($server, $payload), ['action' => $action]);
        } else {
            $base = array_merge($base, $payload);
        }

        $job = PanelJob::query()->create([
            'type' => "server.{$action}",
            'status' => 'pending',
            'payload' => $base,
            'node_id' => $server->node_id,
            'server_id' => $server->id,
            'progress' => 0,
        ]);

        if (in_array($action, ['start', 'restart'], true)) {
            $server->update(['status' => 'starting']);
        } elseif ($action === 'stop') {
            $server->update(['status' => 'stopping']);
        } elseif ($action === 'install') {
            $server->update(['status' => 'installing']);
        } elseif ($action === 'kill') {
            $server->update(['status' => 'stopping']);
        }

        $this->audit->log("server.{$action}", $server, ['job_uuid' => $job->uuid]);

        return $job;
    }
}
