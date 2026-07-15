<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Symfony\Component\HttpFoundation\Response;

class ThrottleApiRequests
{
    public function handle(Request $request, Closure $next, int $maxAttempts = 120, int $decaySeconds = 60): Response
    {
        $key = 'api:'.($request->user()?->id ?? $request->ip()).':'.$request->path();

        if (RateLimiter::tooManyAttempts($key, $maxAttempts)) {
            return response()->json(['message' => 'Too many requests'], 429);
        }

        RateLimiter::hit($key, $decaySeconds);

        return $next($request);
    }
}
