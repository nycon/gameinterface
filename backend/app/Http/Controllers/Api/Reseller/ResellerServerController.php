<?php

namespace App\Http\Controllers\Api\Reseller;

use App\Http\Controllers\Controller;
use App\Models\Server;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\InstallPayloadBuilder;
use App\Services\ServerPowerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ResellerServerController extends Controller
{
    public function __construct(
        private readonly ServerPowerService $power,
        private readonly InstallPayloadBuilder $installPayload,
        private readonly AuditLogger $audit,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $reseller = $request->user();
        $customerIds = User::query()->where('reseller_id', $reseller->id)->pluck('id');

        return response()->json(
            Server::query()
                ->whereIn('user_id', $customerIds)
                ->with(['owner:id,name,email', 'node:id,name', 'template:id,name,slug'])
                ->latest()
                ->paginate(25)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $reseller = $request->user();
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'user_id' => ['required', 'exists:users,id'],
            'node_id' => ['required', 'exists:nodes,id'],
            'game_template_id' => ['required', 'exists:game_templates,id'],
            'image_version_id' => ['nullable', 'exists:image_versions,id'],
            'cpu_quota' => ['nullable', 'string'],
            'memory_max' => ['nullable', 'string'],
            'startup_command' => ['nullable', 'string'],
        ]);

        $owner = User::query()->findOrFail($data['user_id']);
        abort_unless((int) $owner->reseller_id === (int) $reseller->id, 403);

        $server = Server::query()->create($data + [
            'status' => 'installing',
            'linux_user' => 'gp-s0',
            'install_path' => null,
        ]);

        $server->update([
            'linux_user' => 'gp-s'.$server->id,
            'install_path' => '/srv/gamepanel/servers/server-'.$server->id,
        ]);

        $this->installPayload->claimAllocation($server->fresh());
        $job = $this->power->dispatch($server->fresh(), 'install', [
            'image_version_id' => $data['image_version_id'] ?? null,
        ]);
        $this->audit->log('reseller.server.created', $server, ['job_uuid' => $job->uuid]);

        return response()->json([
            'server' => $server->fresh()->load(['owner', 'node', 'template']),
            'job' => $job,
        ], 201);
    }

    public function power(Request $request, Server $server, string $action): JsonResponse
    {
        $reseller = $request->user();
        $owner = $server->owner;
        abort_unless($owner && (int) $owner->reseller_id === (int) $reseller->id, 403);

        $job = $this->power->dispatch($server, $action);

        return response()->json(['job' => $job]);
    }
}
