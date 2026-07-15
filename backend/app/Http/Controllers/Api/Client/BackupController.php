<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\Backup;
use App\Models\Server;
use App\Services\ServerPowerService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class BackupController extends Controller
{
    public function __construct(private readonly ServerPowerService $power) {}

    public function index(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        return response()->json(
            $server->backups()->latest('created_at')->paginate(25)
        );
    }

    public function store(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('update', $server);

        $job = $this->power->dispatch($server, 'backup', [
            'name' => $request->input('name', 'backup-'.now()->format('Ymd-His')),
        ]);

        Backup::query()->create([
            'server_id' => $server->id,
            'name' => $job->payload['name'] ?? 'backup',
            'path' => '',
            'size_bytes' => 0,
            'status' => 'pending',
        ]);

        return response()->json(['job' => $job], 202);
    }

    public function restore(Request $request, Server $server, Backup $backup): JsonResponse
    {
        Gate::authorize('update', $server);
        abort_unless($backup->server_id === $server->id, 404);

        $job = $this->power->dispatch($server, 'restore', [
            'archive_path' => $backup->path,
            'backup_uuid' => $backup->uuid,
        ]);

        $backup->update(['status' => 'restoring']);

        return response()->json(['job' => $job], 202);
    }

    public function destroy(Server $server, Backup $backup): JsonResponse
    {
        Gate::authorize('update', $server);
        abort_unless($backup->server_id === $server->id, 404);

        $backup->delete();

        return response()->json(null, 204);
    }
}
