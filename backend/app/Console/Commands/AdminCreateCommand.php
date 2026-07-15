<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Spatie\Permission\Models\Role;

class AdminCreateCommand extends Command
{
    protected $signature = 'gamepanel:admin-create
        {--name=Admin : Display name}
        {--email= : Admin email}
        {--password= : Admin password}';

    protected $description = 'Create or update a GamePanel admin user';

    public function handle(): int
    {
        $email = $this->option('email') ?: $this->ask('Email');
        $password = $this->option('password') ?: $this->secret('Password');
        $name = $this->option('name');

        Role::findOrCreate('admin');

        $user = User::query()->updateOrCreate(
            ['email' => $email],
            [
                'name' => $name,
                'password' => $password,
                'is_admin' => true,
            ]
        );
        $user->syncRoles(['admin']);

        $this->info("Admin ready: {$user->email}");

        return self::SUCCESS;
    }
}
