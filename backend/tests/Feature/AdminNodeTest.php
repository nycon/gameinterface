<?php

namespace Tests\Feature;

use App\Models\Node;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class AdminNodeTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        Role::findOrCreate('admin');
        $user = User::factory()->create(['is_admin' => true]);
        $user->assignRole('admin');

        return $user;
    }

    public function test_admin_can_create_node_and_receive_token(): void
    {
        Sanctum::actingAs($this->admin());

        $response = $this->postJson('/api/admin/nodes', [
            'name' => 'node-01',
            'hostname' => 'node01.local',
            'ip_address' => '10.0.0.10',
        ]);

        $response->assertCreated()
            ->assertJsonPath('node.name', 'node-01')
            ->assertJsonStructure(['token']);

        $this->assertDatabaseHas('nodes', ['name' => 'node-01']);
    }

    public function test_customer_cannot_list_nodes(): void
    {
        Role::findOrCreate('customer');
        $user = User::factory()->create(['is_admin' => false]);
        $user->assignRole('customer');
        Sanctum::actingAs($user);

        $this->getJson('/api/admin/nodes')->assertForbidden();
    }
}
