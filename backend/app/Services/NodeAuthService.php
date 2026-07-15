<?php

namespace App\Services;

use App\Models\Node;
use App\Models\NodeToken;
use Illuminate\Support\Str;

class NodeAuthService
{
    /**
     * @return array{token: string, model: NodeToken}
     */
    public function createToken(Node $node, string $name = 'default'): array
    {
        $plain = 'gpn_'.Str::random(48);

        $model = $node->tokens()->create([
            'token_hash' => hash('sha256', $plain),
            'name' => $name,
        ]);

        return ['token' => $plain, 'model' => $model];
    }

    public function findNodeByToken(string $plain): ?Node
    {
        $hash = hash('sha256', $plain);

        $token = NodeToken::query()
            ->with('node')
            ->where('token_hash', $hash)
            ->first();

        if (! $token || ! $token->node) {
            return null;
        }

        if ($token->expires_at && $token->expires_at->isPast()) {
            return null;
        }

        $token->forceFill(['last_used_at' => now()])->save();

        return $token->node;
    }

    public function verify(string $plain, string $hash): bool
    {
        return hash_equals($hash, hash('sha256', $plain));
    }
}
