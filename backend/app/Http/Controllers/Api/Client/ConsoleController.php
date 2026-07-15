<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\Server;
use App\Models\ServerEvent;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class ConsoleController extends Controller
{
    public function command(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('power', $server);

        $data = $request->validate([
            'command' => ['required', 'string', 'max:2000'],
        ]);

        $job = \App\Models\PanelJob::query()->create([
            'type' => 'server.console.command',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'server_uuid' => $server->uuid,
                'install_path' => $server->install_path,
                'linux_user' => $server->linux_user,
                'command' => $data['command'],
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        return response()->json(['job' => $job], 202);
    }

    public function history(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        $limit = min(500, max(1, (int) $request->input('limit', 100)));

        $events = ServerEvent::query()
            ->where('server_id', $server->id)
            ->whereIn('type', ['console.output', 'console.history', 'server.log'])
            ->latest('id')
            ->limit($limit)
            ->get()
            ->reverse()
            ->values();

        return response()->json(['events' => $events]);
    }
}
