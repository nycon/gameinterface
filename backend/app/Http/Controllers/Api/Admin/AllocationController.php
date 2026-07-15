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
            'port' => ['required', 'integer', 'min:1', 'max:65535'],
            'protocol' => ['required', 'in:tcp,udp'],
            'notes' => ['nullable', 'string'],
        ]);

        $allocation = Allocation::query()->create($data);

        return response()->json($allocation, 201);
    }

    public function destroy(Allocation $allocation): JsonResponse
    {
        $allocation->delete();

        return response()->json(null, 204);
    }
}
