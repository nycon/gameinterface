<?php

namespace App\Services;

use App\Models\AuditLog;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class AuditLogger
{
    public function log(
        string $action,
        ?Model $auditable = null,
        ?array $meta = null,
        ?Request $request = null,
    ): AuditLog {
        $request ??= request();

        return AuditLog::query()->create([
            'user_id' => $request?->user()?->id,
            'action' => $action,
            'auditable_type' => $auditable ? $auditable::class : null,
            'auditable_id' => $auditable?->getKey(),
            'ip_address' => $request?->ip(),
            'user_agent' => $request?->userAgent(),
            'meta' => $meta,
            'created_at' => now(),
        ]);
    }
}
