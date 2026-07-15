<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Allocation;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class AllocationController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = Allocation::query()->with(['node:id,name', 'server:id,name']);

        if ($request->filled('node_id')) {
            $query->where('node_id', $request->integer('node_id'));
        }

        return response()->json($query->latest()->paginate(50));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'node_id' => ['required', 'exists:nodes,id'],
            'server_id' => ['nullable', 'exists:servers,id'],
            'ip' => ['required', 'ip'],
            'port' => ['required_without:port_end', 'integer', 'min:1', 'max:65535'],
            'port_start' => ['nullable', 'integer', 'min:1', 'max:65535'],
            'port_end' => ['nullable', 'integer', 'min:1', 'max:65535', 'gte:port_start'],
            'protocol' => ['required', 'in:tcp,udp'],
            'notes' => ['nullable', 'string'],
        ]);

        // Einzelport oder Range (port_start..port_end)
        if (! empty($data['port_end'])) {
            $start = (int) ($data['port_start'] ?? $data['port'] ?? 25565);
            $end = (int) $data['port_end'];
            $created = [];
            for ($port = $start; $port <= $end; $port++) {
                $created[] = Allocation::query()->firstOrCreate(
                    [
                        'node_id' => $data['node_id'],
                        'ip' => $data['ip'],
                        'port' => $port,
                        'protocol' => $data['protocol'],
                    ],
                    [
                        'server_id' => $data['server_id'] ?? null,
                        'notes' => $data['notes'] ?? 'pool',
                    ]
                );
            }

            return response()->json(['allocations' => $created, 'count' => count($created)], 201);
        }

        $allocation = Allocation::query()->create([
            'node_id' => $data['node_id'],
            'server_id' => $data['server_id'] ?? null,
            'ip' => $data['ip'],
            'port' => $data['port'],
            'protocol' => $data['protocol'],
            'notes' => $data['notes'] ?? null,
        ]);

        return response()->json($allocation, 201);
    }

    public function destroy(Allocation $allocation): JsonResponse
    {
        $allocation->delete();

        return response()->json(null, 204);
    }
}
