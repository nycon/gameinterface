<?php

namespace App\Http\Controllers\Api\Client;

use App\Http\Controllers\Controller;
use App\Models\PanelJob;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class JobController extends Controller
{
    public function show(Request $request, PanelJob $job): JsonResponse
    {
        $job->loadMissing('server');

        if ($job->server) {
            Gate::authorize('view', $job->server);
        } elseif (! $request->user()->is_admin && ! $request->user()->hasRole('admin')) {
            abort(403);
        }

        return response()->json(['job' => $job]);
    }
}
