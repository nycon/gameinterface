<?php

namespace App\Http\Middleware;

use App\Services\NodeAuthService;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AuthenticateNode
{
    public function __construct(private readonly NodeAuthService $nodeAuth) {}

    public function handle(Request $request, Closure $next): Response
    {
        $header = $request->bearerToken()
            ?? $request->header('X-Node-Token');

        if (! $header) {
            return response()->json(['message' => 'Node token required'], 401);
        }

        $node = $this->nodeAuth->findNodeByToken($header);
        if (! $node) {
            return response()->json(['message' => 'Invalid node token'], 401);
        }

        $request->attributes->set('node', $node);
        $request->setUserResolver(fn () => $node);

        return $next($request);
    }
}
