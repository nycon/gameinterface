<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_login_returns_token(): void
    {
        Role::findOrCreate('admin');
        $user = User::factory()->create([
            'email' => 'admin@example.com',
            'password' => 'secret-password-123',
            'is_admin' => true,
        ]);
        $user->assignRole('admin');

        $response = $this->postJson('/api/auth/login', [
            'email' => 'admin@example.com',
            'password' => 'secret-password-123',
        ]);

        $response->assertOk()->assertJsonStructure(['token', 'user' => ['email']]);
    }

    public function test_me_requires_auth(): void
    {
        $this->getJson('/api/auth/me')->assertUnauthorized();
    }
}
