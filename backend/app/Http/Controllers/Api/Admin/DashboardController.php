<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Node;
use App\Models\PanelJob;
use App\Models\Server;
use App\Models\User;
use Illuminate\Http\JsonResponse;

class DashboardController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'stats' => [
                'users' => User::query()->count(),
                'nodes' => Node::query()->count(),
                'nodes_online' => Node::query()->where('status', 'online')->count(),
                'servers' => Server::query()->count(),
                'servers_online' => Server::query()->where('status', 'online')->count(),
                'jobs_pending' => PanelJob::query()->where('status', 'pending')->count(),
                'jobs_running' => PanelJob::query()->where('status', 'running')->count(),
            ],
            'recent_servers' => Server::query()->with(['owner:id,name', 'node:id,name'])->latest()->limit(8)->get(),
            'recent_jobs' => PanelJob::query()->latest()->limit(8)->get(),
        ]);
    }
}
