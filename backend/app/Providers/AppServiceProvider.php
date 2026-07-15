<?php

namespace App\Providers;

use App\Models\Server;
use App\Policies\ServerPolicy;
use Illuminate\Support\Facades\Broadcast;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        Gate::policy(Server::class, ServerPolicy::class);

        Broadcast::routes(['middleware' => ['auth:sanctum']]);
    }
}
