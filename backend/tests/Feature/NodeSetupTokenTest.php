<?php

namespace Tests\Feature;

use App\Models\Setting;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NodeSetupTokenTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_requires_setup_token_when_configured(): void
    {
        Setting::setValue('security.node_setup_token', 'gps_testtoken_abcdefghijklmnopqrstuvwxyz');

        $this->postJson('/api/node/register', [
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.5',
        ])->assertForbidden();

        $this->postJson('/api/node/register', [
            'name' => 'n1',
            'hostname' => 'n1',
            'ip_address' => '10.0.0.5',
            'setup_token' => 'gps_testtoken_abcdefghijklmnopqrstuvwxyz',
        ])->assertCreated()->assertJsonStructure(['token', 'node' => ['uuid']]);
    }
}
