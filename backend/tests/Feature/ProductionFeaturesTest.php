<?php

namespace Tests\Feature;

use App\Models\Backup;
use App\Models\Node;
use App\Models\PanelJob;
use App\Models\Server;
use App\Models\User;
use App\Services\NodeAuthService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\TestCase;

class ProductionFeaturesTest extends TestCase
{
    use RefreshDatabase;

    private function customerWithServer(): array
    {
        Role::findOrCreate('customer');
        $user = User::factory()->create(['is_admin' => false]);
        $user->assignRole('customer');
        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.1',
            'status' => 'online',
        ]);
        $template = \App\Models\GameTemplate::query()->create([
            'name' => 'Test',
            'slug' => 'test-'.uniqid(),
            'type' => 'custom',
            'yaml_definition' => "name: Test\n",
            'is_active' => true,
        ]);
        $server = Server::query()->create([
            'name' => 's1',
            'user_id' => $user->id,
            'node_id' => $node->id,
            'game_template_id' => $template->id,
            'status' => 'offline',
            'linux_user' => 'gp-s1',
            'install_path' => '/srv/gamepanel/servers/server-1',
        ]);

        return [$user, $node, $server];
    }

    public function test_client_can_poll_own_job(): void
    {
        [$user, $node, $server] = $this->customerWithServer();
        $job = PanelJob::query()->create([
            'type' => 'server.files.list',
            'status' => 'completed',
            'payload' => ['path' => '/'],
            'result' => ['entries' => [['name' => 'server.cfg', 'is_dir' => false]]],
            'node_id' => $node->id,
            'server_id' => $server->id,
        ]);

        Sanctum::actingAs($user);

        $this->getJson('/api/client/jobs/'.$job->uuid)
            ->assertOk()
            ->assertJsonPath('job.result.entries.0.name', 'server.cfg');
    }

    public function test_backup_job_status_creates_backup_row(): void
    {
        [$user, $node, $server] = $this->customerWithServer();
        $job = PanelJob::query()->create([
            'type' => 'server.backup',
            'status' => 'running',
            'payload' => ['name' => 'nightly'],
            'node_id' => $node->id,
            'server_id' => $server->id,
        ]);

        $token = app(NodeAuthService::class)->createToken($node, 'agent');

        $this->withToken($token['token'])
            ->postJson('/api/node/jobs/'.$job->uuid.'/status', [
                'status' => 'completed',
                'result' => [
                    'path' => '/srv/backups/nightly.tar.zst',
                    'size_bytes' => 1234,
                    'checksum_sha256' => 'abc',
                ],
            ])
            ->assertOk();

        $this->assertDatabaseHas('backups', [
            'server_id' => $server->id,
            'name' => 'nightly',
            'path' => '/srv/backups/nightly.tar.zst',
            'status' => 'completed',
        ]);
    }

    public function test_install_payload_includes_template_fields(): void
    {
        Role::findOrCreate('admin');
        $admin = User::factory()->create(['is_admin' => true]);
        $admin->assignRole('admin');
        $customer = User::factory()->create(['is_admin' => false]);
        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.2',
            'status' => 'online',
        ]);
        $template = \App\Models\GameTemplate::query()->create([
            'name' => 'CS2',
            'slug' => 'cs2',
            'type' => 'steam',
            'steam_app_id' => '730',
            'yaml_definition' => "name: CS2\n",
            'is_active' => true,
        ]);

        Sanctum::actingAs($admin);

        $response = $this->postJson('/api/admin/servers', [
            'name' => 'cs2-1',
            'user_id' => $customer->id,
            'node_id' => $node->id,
            'game_template_id' => $template->id,
            'memory_max' => '4G',
        ])->assertCreated();

        $jobId = $response->json('job.id');
        $job = PanelJob::query()->findOrFail($jobId);
        $this->assertSame('730', $job->payload['steam_app_id'] ?? null);
        $this->assertNotEmpty($job->payload['install_path'] ?? null);
    }

    public function test_reseller_scoped_user_create(): void
    {
        Role::findOrCreate('reseller');
        Role::findOrCreate('customer');
        $reseller = User::factory()->create(['is_admin' => false]);
        $reseller->assignRole('reseller');

        Sanctum::actingAs($reseller);

        $response = $this->postJson('/api/reseller/users', [
            'name' => 'Cust',
            'email' => 'cust@example.com',
            'password' => 'password12345',
        ]);
        $response->assertCreated();

        $this->assertDatabaseHas('users', [
            'email' => 'cust@example.com',
            'reseller_id' => $reseller->id,
        ]);
    }

    public function test_two_factor_challenge_flow(): void
    {
        $user = User::factory()->create([
            'email' => 'tfa@example.com',
            'password' => 'password12345',
            'is_admin' => false,
        ]);

        $totp = app(\App\Services\TotpService::class);
        $enc = app(\App\Services\EncryptionService::class);
        $secret = $totp->generateSecret();
        $user->update([
            'two_factor_secret' => $enc->encrypt($secret),
            'two_factor_confirmed_at' => now(),
            'two_factor_recovery_codes' => json_encode([]),
        ]);

        $login = $this->postJson('/api/auth/login', [
            'email' => 'tfa@example.com',
            'password' => 'password12345',
        ])->assertOk()->assertJsonPath('two_factor', true);

        $challenge = $login->json('challenge');
        $code = $totp->code($secret);

        $this->postJson('/api/auth/two-factor-challenge', [
            'challenge' => $challenge,
            'code' => $code,
        ])->assertOk()->assertJsonStructure(['token', 'user']);
    }
}
