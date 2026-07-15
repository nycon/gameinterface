<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\Server;
use App\Services\ServerPowerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class ServerController extends Controller
{
    public function __construct(private readonly ServerPowerService $power) {}

    public function index(Request $request): JsonResponse
    {
        $query = Server::query()->with(['node:id,name', 'template:id,name,slug']);

        if (! $request->user()->is_admin && ! $request->user()->hasRole('admin')) {
            $query->where('user_id', $request->user()->id);
        }

        return response()->json($query->latest()->paginate(25));
    }

    public function show(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        return response()->json(
            $server->load(['node', 'template', 'allocations', 'variables', 'backups'])
        );
    }

    public function power(Request $request, Server $server, string $action): JsonResponse
    {
        Gate::authorize('power', $server);

        $job = $this->power->dispatch($server, $action);

        return response()->json(['job' => $job]);
    }
}
