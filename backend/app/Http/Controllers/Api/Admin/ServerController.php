<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Server;
use App\Services\AuditLogger;
use App\Services\InstallPayloadBuilder;
use App\Services\ServerPowerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ServerController extends Controller
{
    public function __construct(
        private readonly ServerPowerService $power,
        private readonly AuditLogger $audit,
        private readonly InstallPayloadBuilder $installPayload,
    ) {}

    public function index(): JsonResponse
    {
        return response()->json(
            Server::query()->with(['owner:id,name,email', 'node:id,name', 'template:id,name,slug', 'allocations'])
                ->latest()->paginate(25)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'user_id' => ['required', 'exists:users,id'],
            'node_id' => ['required', 'exists:nodes,id'],
            'game_template_id' => ['required', 'exists:game_templates,id'],
            'image_version_id' => ['nullable', 'exists:image_versions,id'],
            'cpu_quota' => ['nullable', 'string'],
            'memory_max' => ['nullable', 'string'],
            'startup_command' => ['nullable', 'string'],
            'auto_install' => ['sometimes', 'boolean'],
        ]);

        $autoInstall = $data['auto_install'] ?? true;
        unset($data['auto_install']);

        $server = Server::query()->create($data + [
            'status' => $autoInstall ? 'installing' : 'offline',
            'linux_user' => 'gp-s0',
            'install_path' => null,
        ]);

        $server->update([
            'linux_user' => 'gp-s'.$server->id,
            'install_path' => '/srv/gamepanel/servers/server-'.$server->id,
        ]);

        $this->installPayload->claimAllocation($server->fresh());

        $job = null;
        if ($autoInstall) {
            $job = $this->power->dispatch($server->fresh(), 'install', [
                'image_version_id' => $data['image_version_id'] ?? null,
            ]);
        }

        $this->audit->log('server.created', $server, ['job_uuid' => $job?->uuid]);

        return response()->json([
            'server' => $server->fresh()->load(['owner', 'node', 'template', 'allocations']),
            'job' => $job,
        ], 201);
    }

    public function show(Server $server): JsonResponse
    {
        return response()->json(
            $server->load(['owner', 'node', 'template', 'imageVersion', 'allocations', 'variables'])
        );
    }

    public function update(Request $request, Server $server): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'cpu_quota' => ['nullable', 'string'],
            'memory_max' => ['nullable', 'string'],
            'startup_command' => ['nullable', 'string'],
            'status' => ['sometimes', 'string'],
        ]);

        $server->update($data);
        $this->audit->log('server.updated', $server);

        return response()->json($server);
    }

    public function destroy(Server $server): JsonResponse
    {
        $server->loadMissing('node');

        // Node aufräumen (Stop + Unit + Dateien) — best effort
        $uninstallJob = null;
        try {
            $uninstallJob = $this->power->dispatch($server, 'uninstall');
        } catch (\Throwable) {
            // weiter löschen, auch wenn Node offline / Job fehlschlägt
        }

        $server->allocations()->update(['server_id' => null]);

        // andere pending Jobs abbrechen — den Uninstall-Job aber laufen lassen
        $pending = $server->panelJobs()->whereIn('status', ['pending', 'running']);
        if ($uninstallJob) {
            $pending->where('id', '!=', $uninstallJob->id);
        }
        $pending->update([
            'status' => 'failed',
            'error' => 'server deleted',
            'finished_at' => now(),
        ]);

        $server->delete();
        $this->audit->log('server.deleted', $server);

        return response()->json(['ok' => true], 200);
    }

    public function power(Request $request, Server $server, string $action): JsonResponse
    {
        $job = $this->power->dispatch($server, $action);

        return response()->json(['job' => $job]);
    }
}
