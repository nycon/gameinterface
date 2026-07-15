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
        $database->loadMissing(['server.node:id,name,hostname,ip_address,phpmyadmin_url,mysql_admin_user']);
        $node = $database->server?->node;
        $phpmyadmin = $node?->phpmyadmin_url;
        if (! filled($phpmyadmin) && $node) {
            $phpmyadmin = \App\Models\Node::preferredPhpmyadminUrl((string) $node->hostname, (string) $node->ip_address);
        }

        return response()->json([
            'database' => $database,
            'password' => $this->encryption->decrypt($database->password_encrypted),
            'phpmyadmin_url' => $phpmyadmin,
        ]);
    }

    public function nodeAccess(Request $request): JsonResponse
    {
        $nodeId = $request->integer('node_id');
        abort_unless($nodeId > 0, 422, 'node_id required');

        $node = \App\Models\Node::query()->findOrFail($nodeId);
        $phpmyadmin = $node->phpmyadmin_url
            ?: \App\Models\Node::preferredPhpmyadminUrl((string) $node->hostname, (string) $node->ip_address);

        return response()->json([
            'node' => $node->only(['id', 'name', 'ip_address', 'hostname', 'phpmyadmin_url', 'mysql_admin_user']),
            'phpmyadmin_url' => $phpmyadmin,
            'username' => $node->mysql_admin_user ?: 'gamepanel-agent',
            'password' => $this->encryption->decrypt($node->mysql_admin_password_encrypted),
        ]);
    }
}
