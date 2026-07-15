<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Node;
use App\Services\AuditLogger;
use App\Services\DeployTokenService;
use App\Services\InstallPayloadBuilder;
use App\Services\NodeAuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NodeController extends Controller
{
    public function __construct(
        private readonly NodeAuthService $nodeAuth,
        private readonly DeployTokenService $deployTokens,
        private readonly AuditLogger $audit,
        private readonly InstallPayloadBuilder $installPayload,
    ) {}

    public function index(): JsonResponse
    {
        return response()->json(
            Node::query()->withCount('servers')->latest()->paginate(25)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'hostname' => ['required', 'string', 'max:255'],
            'ip_address' => ['required', 'ip'],
            'cpu_cores' => ['nullable', 'integer', 'min:1'],
            'memory_mb' => ['nullable', 'integer', 'min:1'],
            'disk_gb' => ['nullable', 'integer', 'min:1'],
        ]);

        $node = Node::query()->create($data + [
            'status' => 'offline',
            'phpmyadmin_url' => 'http://'.$data['ip_address'].':8081/',
        ]);

        // Port-Pool vorbereiten (Minecraft 25565+), damit Server-Install ohne manuellen Port läuft
        $this->installPayload->seedNodeAllocations($node);

        $deploy = $this->deployTokens->createFor(
            $node,
            DeployTokenService::PURPOSE_NODE,
            $request->user(),
        );

        $this->audit->log('node.created', $node);

        return response()->json([
            'node' => $node->fresh()->loadCount('servers')->loadCount('allocations'),
            'deploy_token' => $deploy['token'],
            'install_command' => $deploy['install_command'],
            // Legacy field kept for older clients
            'token' => $deploy['token'],
        ], 201);
    }

    public function show(Node $node): JsonResponse
    {
        $node->load(['servers', 'allocations'])->loadCount('servers');

        return response()->json($node);
    }

    public function update(Request $request, Node $node): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'hostname' => ['sometimes', 'string', 'max:255'],
            'ip_address' => ['sometimes', 'ip'],
            'status' => ['sometimes', 'in:offline,online,maintenance'],
            'cpu_cores' => ['nullable', 'integer'],
            'memory_mb' => ['nullable', 'integer'],
            'disk_gb' => ['nullable', 'integer'],
        ]);

        $node->update($data);
        $this->audit->log('node.updated', $node);

        return response()->json($node);
    }

    public function destroy(Node $node): JsonResponse
    {
        $node->delete();
        $this->audit->log('node.deleted', $node);

        return response()->json(null, 204);
    }

    public function createToken(Request $request, Node $node): JsonResponse
    {
        $data = $request->validate([
            'name' => ['nullable', 'string', 'max:255'],
        ]);

        $token = $this->nodeAuth->createToken($node, $data['name'] ?? 'default');
        $this->audit->log('node.token_created', $node);

        return response()->json([
            'token' => $token['token'],
            'name' => $token['model']->name,
        ], 201);
    }

    public function createDeployToken(Request $request, Node $node): JsonResponse
    {
        $deploy = $this->deployTokens->createFor(
            $node,
            DeployTokenService::PURPOSE_NODE,
            $request->user(),
        );
        $this->audit->log('node.deploy_token_created', $node);

        return response()->json([
            'deploy_token' => $deploy['token'],
            'install_command' => $deploy['install_command'],
        ], 201);
    }
}
