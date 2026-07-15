<?php

namespace Tests\Feature;

use App\Models\Node;
use App\Models\PanelJob;
use App\Services\NodeAuthService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NodeAgentTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_returns_token(): void
    {
        $response = $this->postJson('/api/node/register', [
            'name' => 'bare-metal-01',
            'hostname' => 'bm01',
            'ip_address' => '192.168.1.50',
            'agent_version' => '0.1.0',
        ]);

        $response->assertCreated()->assertJsonStructure(['token', 'node' => ['uuid']]);
    }

    public function test_heartbeat_and_job_claim(): void
    {
        $node = Node::query()->create([
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.5',
            'status' => 'offline',
        ]);

        $auth = app(NodeAuthService::class);
        $token = $auth->createToken($node)['token'];

        PanelJob::query()->create([
            'type' => 'server.start',
            'status' => 'pending',
            'payload' => ['action' => 'start'],
            'node_id' => $node->id,
        ]);

        $this->withToken($token)
            ->postJson('/api/node/heartbeat', ['agent_version' => '0.1.0'])
            ->assertOk();

        $this->assertDatabaseHas('nodes', ['id' => $node->id, 'status' => 'online']);

        $jobs = $this->withToken($token)->getJson('/api/node/jobs');
        $jobs->assertOk();
        $this->assertCount(1, $jobs->json('jobs'));
        $this->assertSame('running', $jobs->json('jobs.0.status'));
    }
}
