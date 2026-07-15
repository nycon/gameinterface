<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\PanelJob;
use App\Models\Server;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class FileController extends Controller
{
    public function index(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        $path = $request->string('path', '/')->toString();

        $job = PanelJob::query()->create([
            'type' => 'server.files.list',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'server_uuid' => $server->uuid,
                'install_path' => $server->install_path,
                'path' => $path,
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        return response()->json([
            'job' => $job,
            'message' => 'File listing queued on node agent',
        ]);
    }

    public function content(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        $data = $request->validate([
            'path' => ['required', 'string'],
        ]);

        $job = PanelJob::query()->create([
            'type' => 'server.files.read',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'server_uuid' => $server->uuid,
                'install_path' => $server->install_path,
                'path' => $data['path'],
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        return response()->json(['job' => $job]);
    }

    public function write(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('update', $server);

        $data = $request->validate([
            'path' => ['required', 'string'],
            'content' => ['required', 'string'],
        ]);

        $job = PanelJob::query()->create([
            'type' => 'server.files.write',
            'status' => 'pending',
            'payload' => $data + [
                'server_id' => $server->id,
                'server_uuid' => $server->uuid,
                'install_path' => $server->install_path,
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        return response()->json(['job' => $job], 202);
    }
}
