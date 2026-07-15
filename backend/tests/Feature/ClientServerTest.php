<?php

namespace Tests\Feature;

use App\Models\GameTemplate;
use App\Models\Node;
use App\Models\Server;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ClientServerTest extends TestCase
{
    use RefreshDatabase;

    public function test_customer_sees_only_own_servers(): void
    {
        Role::findOrCreate('customer');
        $owner = User::factory()->create(['is_admin' => false]);
        $other = User::factory()->create(['is_admin' => false]);
        $owner->assignRole('customer');

        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.1',
            'status' => 'online',
        ]);
        $template = GameTemplate::query()->create([
            'name' => 'Minecraft',
            'slug' => 'minecraft',
            'type' => 'minecraft',
            'yaml_definition' => "name: Minecraft\n",
        ]);

        Server::query()->create([
            'name' => 'mine',
            'user_id' => $owner->id,
            'node_id' => $node->id,
            'game_template_id' => $template->id,
            'status' => 'offline',
            'linux_user' => 'gp-s1',
            'install_path' => '/srv/gamepanel/servers/server-1',
        ]);
        Server::query()->create([
            'name' => 'other',
            'user_id' => $other->id,
            'node_id' => $node->id,
            'game_template_id' => $template->id,
            'status' => 'offline',
            'linux_user' => 'gp-s2',
            'install_path' => '/srv/gamepanel/servers/server-2',
        ]);

        Sanctum::actingAs($owner);
        $response = $this->getJson('/api/client/servers');
        $response->assertOk();
        $this->assertCount(1, $response->json('data'));
    }

    public function test_start_creates_panel_job(): void
    {
        Role::findOrCreate('customer');
        $owner = User::factory()->create(['is_admin' => false]);
        $owner->assignRole('customer');
        $node = Node::query()->create([
            'name' => 'n1', 'hostname' => 'n1', 'ip_address' => '10.0.0.1', 'status' => 'online',
        ]);
        $template = GameTemplate::query()->create([
            'name' => 'CS2', 'slug' => 'cs2', 'type' => 'steam', 'yaml_definition' => "name: CS2\n",
        ]);
        $server = Server::query()->create([
            'name' => 'cs', 'user_id' => $owner->id, 'node_id' => $node->id,
            'game_template_id' => $template->id, 'status' => 'offline',
            'linux_user' => 'gp-s1', 'install_path' => '/srv/gamepanel/servers/server-1',
        ]);

        Sanctum::actingAs($owner);
        $this->postJson("/api/client/servers/{$server->id}/start")
            ->assertOk()
            ->assertJsonPath('job.type', 'server.start');

        $this->assertDatabaseHas('panel_jobs', [
            'server_id' => $server->id,
            'type' => 'server.start',
            'status' => 'pending',
        ]);
    }
}
