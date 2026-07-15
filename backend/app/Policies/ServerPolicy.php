<?php

namespace App\Policies;

use App\Models\Server;
use App\Models\User;

class ServerPolicy
{
    public function viewAny(User $user): bool
    {
        return true;
    }

    public function view(User $user, Server $server): bool
    {
        if ($user->is_admin || $user->hasRole('admin')) {
            return true;
        }
        if ($server->user_id === $user->id) {
            return true;
        }
        if ($user->hasRole('reseller')) {
            $owner = $server->owner;

            return $owner && (int) $owner->reseller_id === (int) $user->id;
        }

        return false;
    }

    public function create(User $user): bool
    {
        return $user->is_admin || $user->hasRole('admin') || $user->hasRole('reseller');
    }

    public function update(User $user, Server $server): bool
    {
        return $this->view($user, $server);
    }

    public function delete(User $user, Server $server): bool
    {
        return $user->is_admin || $user->hasRole('admin');
    }

    public function power(User $user, Server $server): bool
    {
        return $this->view($user, $server);
    }
}
