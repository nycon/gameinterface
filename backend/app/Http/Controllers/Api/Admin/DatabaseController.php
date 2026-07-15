<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\ServerDatabase;
use App\Services\EncryptionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class DatabaseController extends Controller
{
    public function __construct(private readonly EncryptionService $encryption) {}

    public function index(Request $request): JsonResponse
    {
        $query = ServerDatabase::query()
            ->with([
                'server:id,name,user_id,node_id',
                'server.owner:id,name,email',
                'server.node:id,name,ip_address,phpmyadmin_url',
            ])
            ->latest();

        if ($request->filled('server_id')) {
            $query->where('server_id', $request->integer('server_id'));
        }
        if ($request->filled('node_id')) {
            $query->whereHas('server', fn ($q) => $q->where('node_id', $request->integer('node_id')));
        }

        return response()->json($query->paginate(50));
    }

    public function reveal(ServerDatabase $database): JsonResponse
    {
        $database->loadMissing(['server.node:id,name,ip_address,phpmyadmin_url,mysql_admin_user']);

        return response()->json([
            'database' => $database,
            'password' => $this->encryption->decrypt($database->password_encrypted),
            'phpmyadmin_url' => $database->server?->node?->phpmyadmin_url
                ?: ($database->server?->node?->ip_address
                    ? 'https://'.$database->server->node->ip_address.'/'
                    : null),
        ]);
    }

    public function nodeAccess(Request $request): JsonResponse
    {
        $nodeId = $request->integer('node_id');
        abort_unless($nodeId > 0, 422, 'node_id required');

        $node = \App\Models\Node::query()->findOrFail($nodeId);

        return response()->json([
            'node' => $node->only(['id', 'name', 'ip_address', 'phpmyadmin_url', 'mysql_admin_user']),
            'phpmyadmin_url' => $node->phpmyadmin_url
                ?: ($node->ip_address ? 'https://'.$node->ip_address.'/' : null),
            'username' => $node->mysql_admin_user ?: 'gamepanel-agent',
            'password' => $this->encryption->decrypt($node->mysql_admin_password_encrypted),
        ]);
    }
}
