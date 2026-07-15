<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\PanelJob;
use App\Models\Server;
use App\Models\ServerDatabase;
use App\Services\EncryptionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Str;

class DatabaseController extends Controller
{
    public function __construct(private readonly EncryptionService $encryption) {}

    public function index(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        return response()->json($server->databases);
    }

    public function store(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('update', $server);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:64', 'regex:/^[a-zA-Z0-9_]+$/'],
            'username' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9_]+$/'],
            'password' => ['nullable', 'string', 'min:12'],
            'host' => ['nullable', 'string'],
            'port' => ['nullable', 'integer'],
            'engine' => ['nullable', 'in:mariadb,mysql'],
        ]);

        $password = $data['password'] ?? Str::password(20);
        $username = $data['username'] ?? ('gp_'.$server->id.'_'.Str::lower(Str::random(6)));

        $db = ServerDatabase::query()->create([
            'server_id' => $server->id,
            'name' => $data['name'],
            'username' => $username,
            'password_encrypted' => $this->encryption->encrypt($password),
            'host' => $data['host'] ?? '127.0.0.1',
            'port' => $data['port'] ?? 3306,
            'engine' => $data['engine'] ?? 'mariadb',
        ]);

        $job = PanelJob::query()->create([
            'type' => 'server.database.create',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'database_id' => $db->id,
                'name' => $db->name,
                'username' => $db->username,
                'password' => $password,
                'engine' => $db->engine,
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        return response()->json([
            'database' => $db,
            'password' => $password,
            'job' => $job,
        ], 201);
    }

    public function destroy(Server $server, ServerDatabase $database): JsonResponse
    {
        Gate::authorize('update', $server);
        abort_unless($database->server_id === $server->id, 404);

        $job = PanelJob::query()->create([
            'type' => 'server.database.delete',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'database_id' => $database->id,
                'name' => $database->name,
                'username' => $database->username,
                'engine' => $database->engine,
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        $database->delete();

        return response()->json(['job' => $job], 202);
    }
}
