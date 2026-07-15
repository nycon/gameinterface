<?php

use App\Models\Server;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('servers.{serverId}', function ($user, int $serverId) {
    $server = Server::query()->with('owner')->find($serverId);
    if (! $server) {
        return false;
    }

    if ($user->is_admin || $user->hasRole('admin')) {
        return true;
    }

    if ($user->hasRole('reseller') && $server->owner && (int) $server->owner->reseller_id === (int) $user->id) {
        return true;
    }

    return (int) $server->user_id === (int) $user->id;
});
