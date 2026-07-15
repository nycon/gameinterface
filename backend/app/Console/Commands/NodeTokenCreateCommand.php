<?php

namespace App\Console\Commands;

use App\Models\Node;
use App\Services\NodeAuthService;
use Illuminate\Console\Command;

class NodeTokenCreateCommand extends Command
{
    protected $signature = 'gamepanel:node-token-create
        {node : Node ID or UUID}
        {--name=default : Token name}';

    protected $description = 'Create a node agent authentication token';

    public function handle(NodeAuthService $auth): int
    {
        $identifier = $this->argument('node');
        $node = Node::query()
            ->where('id', $identifier)
            ->orWhere('uuid', $identifier)
            ->firstOrFail();

        $token = $auth->createToken($node, (string) $this->option('name'));

        $this->info("Node: {$node->name} ({$node->uuid})");
        $this->line($token['token']);

        return self::SUCCESS;
    }
}
