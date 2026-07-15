<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\PanelJob;
use Illuminate\Http\JsonResponse;

class JobController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(
            PanelJob::query()->with(['node:id,name', 'server:id,name'])->latest()->paginate(50)
        );
    }

    public function show(PanelJob $job): JsonResponse
    {
        return response()->json($job->load(['node', 'server']));
    }
}
