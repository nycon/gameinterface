<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\FtpAccount;
use App\Models\PanelJob;
use App\Models\Server;
use App\Services\EncryptionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Str;

class FtpAccountController extends Controller
{
    public function __construct(private readonly EncryptionService $encryption) {}

    public function index(Server $server): JsonResponse
    {
        Gate::authorize('view', $server);

        $server->loadMissing('node:id,ip_address,hostname');

        return response()->json([
            'data' => $server->ftpAccounts,
            'host' => $server->node?->ip_address,
            'port' => 22,
            'protocol' => 'sftp',
        ]);
    }

    public function store(Request $request, Server $server): JsonResponse
    {
        Gate::authorize('update', $server);

        $data = $request->validate([
            'username' => ['nullable', 'string', 'max:64', 'regex:/^[a-zA-Z0-9_-]+$/'],
            'password' => ['nullable', 'string', 'min:12'],
        ]);

        $username = $data['username'] ?? ('sftp_s'.$server->id.'_'.Str::lower(Str::random(4)));
        $password = $data['password'] ?? Str::password(20);
        // Home = Install-Pfad (Minecraft/CS liegen dort). SFTP-Chroot = Parent (servers/).
        $home = rtrim((string) $server->install_path, '/') ?: ('/srv/gamepanel/servers/server-'.$server->id);

        $account = FtpAccount::query()->create([
            'server_id' => $server->id,
            'username' => $username,
            'password_encrypted' => $this->encryption->encrypt($password),
            'home_path' => $home,
        ]);

        $job = PanelJob::query()->create([
            'type' => 'server.ftp.sync',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'install_path' => $server->install_path,
                'linux_user' => $server->linux_user,
                'username' => $username,
                'password' => $password,
                'home_path' => $home,
                'action' => 'create',
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        $server->loadMissing('node:id,ip_address,hostname');

        return response()->json([
            'ftp_account' => $account,
            'password' => $password,
            'protocol' => 'sftp',
            'host' => $server->node?->ip_address,
            'port' => 22,
            'job' => $job,
        ], 201);
    }

    public function destroy(Server $server, FtpAccount $ftpAccount): JsonResponse
    {
        Gate::authorize('update', $server);
        abort_unless($ftpAccount->server_id === $server->id, 404);

        $job = PanelJob::query()->create([
            'type' => 'server.ftp.sync',
            'status' => 'pending',
            'payload' => [
                'server_id' => $server->id,
                'username' => $ftpAccount->username,
                'action' => 'delete',
            ],
            'node_id' => $server->node_id,
            'server_id' => $server->id,
        ]);

        $ftpAccount->delete();

        return response()->json(['job' => $job], 202);
    }
}
