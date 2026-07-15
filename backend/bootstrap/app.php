<?php

use App\Http\Middleware\AuthenticateNode;
use App\Http\Middleware\EnsureUserIsAdmin;
use App\Http\Middleware\ThrottleApiRequests;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        channels: __DIR__.'/../routes/channels.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'admin' => EnsureUserIsAdmin::class,
            'reseller' => \App\Http\Middleware\EnsureUserIsReseller::class,
            'node.auth' => AuthenticateNode::class,
            'throttle.api' => ThrottleApiRequests::class,
        ]);

        $middleware->api(prepend: [
            ThrottleApiRequests::class,
        ]);

        $middleware->statefulApi();
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        //
    })->create();
