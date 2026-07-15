<?php

namespace Tests\Feature;

use App\Models\DeployToken;
use App\Models\ImageServer;
use App\Models\Node;
use App\Models\User;
use App\Services\DeployTokenService;
use App\Services\EncryptionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class DeployFlowTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        Role::findOrCreate('admin');
        $user = User::factory()->create(['is_admin' => true]);
        $user->assignRole('admin');

        return $user;
    }

    public function test_creating_node_returns_install_command(): void
    {
        config(['app.url' => 'https://panel.test']);
        Sanctum::actingAs($this->admin());

        $response = $this->postJson('/api/admin/nodes', [
            'name' => 'node-01',
            'hostname' => 'node01.local',
            'ip_address' => '10.0.0.12',
        ]);

        $response->assertCreated()
            ->assertJsonStructure(['node', 'deploy_token', 'install_command']);

        $cmd = $response->json('install_command');
        $token = $response->json('deploy_token');
        $this->assertStringStartsWith('gpd_', $token);
        $this->assertStringContainsString('/install/node/'.$token.'.sh', $cmd);
        $this->assertStringContainsString('curl -fsSL', $cmd);
    }

    public function test_creating_image_server_deploy_mode_returns_install_command(): void
    {
        config(['app.url' => 'https://panel.test']);
        Sanctum::actingAs($this->admin());

        $response = $this->postJson('/api/admin/image-servers', [
            'name' => 'images-01',
            'mode' => 'deploy',
        ]);

        $response->assertCreated()
            ->assertJsonPath('image_server.status', 'pending')
            ->assertJsonStructure(['deploy_token', 'install_command']);

        $this->assertStringContainsString('/install/image-server/', $response->json('install_command'));
    }

    public function test_node_install_script_contains_panel_url_and_token(): void
    {
        config(['app.url' => 'https://panel.test']);
        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.12',
            'status' => 'offline',
        ]);
        $deploy = app(DeployTokenService::class)->createFor($node, DeployTokenService::PURPOSE_NODE);
        $plain = $deploy['token'];

        $response = $this->get('/install/node/'.$plain.'.sh');
        $response->assertOk();
        $body = $response->getContent();
        $this->assertStringContainsString('PANEL_URL="https://panel.test"', $body);
        $this->assertStringContainsString('DEPLOY_TOKEN="'.$plain.'"', $body);
        $this->assertStringContainsString('--role node', $body);
    }

    public function test_node_claim_returns_config_and_consumes_token(): void
    {
        config(['app.url' => 'https://panel.test']);
        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.12',
            'status' => 'offline',
        ]);
        $deploy = app(DeployTokenService::class)->createFor($node, DeployTokenService::PURPOSE_NODE);
        $plain = $deploy['token'];

        $response = $this->postJson('/api/install/node/claim', [
            'deploy_token' => $plain,
            'hostname' => 'node.local',
            'ip_address' => '10.0.0.55',
            'agent_version' => '1.0.0',
            'tls_insecure' => true,
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'config_yaml', 'node']);
        $this->assertNotEmpty($response->json('token'));
        $this->assertStringContainsString('tls_insecure: true', $response->json('config_yaml'));
        $this->assertDatabaseHas('nodes', [
            'id' => $node->id,
            'ip_address' => '10.0.0.55',
        ]);

        $this->assertNotNull(DeployToken::query()->where('token_hash', hash('sha256', $plain))->value('used_at'));

        $this->postJson('/api/install/node/claim', [
            'deploy_token' => $plain,
        ])->assertForbidden();
    }

    public function test_image_server_complete_stores_key_and_marks_ready(): void
    {
        config(['app.url' => 'https://panel.test']);
        $server = ImageServer::query()->create([
            'name' => 'img',
            'hostname' => 'pending',
            'protocol' => 'sftp',
            'port' => 22,
            'base_path' => '/images',
            'username' => 'gamepanel-images',
            'is_active' => false,
            'status' => 'pending',
        ]);
        $deploy = app(DeployTokenService::class)->createFor($server, DeployTokenService::PURPOSE_IMAGE_SERVER);
        $plain = $deploy['token'];
        $key = "-----BEGIN OPENSSH PRIVATE KEY-----\ntest\n-----END OPENSSH PRIVATE KEY-----";

        $response = $this->postJson('/api/install/image-server/complete', [
            'deploy_token' => $plain,
            'hostname' => '10.0.0.11',
            'username' => 'gamepanel-images',
            'port' => 22,
            'base_path' => '/images',
            'protocol' => 'sftp',
            'ssh_private_key' => $key,
        ]);

        $response->assertOk()->assertJsonPath('ok', true);

        $server->refresh();
        $this->assertSame('ready', $server->status);
        $this->assertTrue($server->is_active);
        $this->assertSame('10.0.0.11', $server->hostname);
        $this->assertSame(
            $key,
            app(EncryptionService::class)->decrypt($server->ssh_key_encrypted)
        );

        $this->postJson('/api/install/image-server/complete', [
            'deploy_token' => $plain,
            'hostname' => '10.0.0.11',
            'username' => 'gamepanel-images',
            'ssh_private_key' => $key,
        ])->assertForbidden();
    }

    public function test_invalid_deploy_token_rejected(): void
    {
        $this->postJson('/api/install/node/claim', [
            'deploy_token' => 'gpd_invalid',
        ])->assertForbidden();

        $this->get('/install/node/gpd_invalid.sh')->assertForbidden();
    }
}
