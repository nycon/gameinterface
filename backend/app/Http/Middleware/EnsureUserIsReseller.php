<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsureUserIsReseller
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if (! $user) {
            abort(401);
        }

        if ($user->is_admin || $user->hasRole('admin') || $user->hasRole('reseller')) {
            return $next($request);
        }

        abort(403, 'Reseller access required');
    }
}
