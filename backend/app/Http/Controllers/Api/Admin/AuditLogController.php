<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\AuditLog;
use Illuminate\Http\JsonResponse;

class AuditLogController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(
            AuditLog::query()->with('user:id,name,email')->latest('created_at')->paginate(50)
        );
    }
}
