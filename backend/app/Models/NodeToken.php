<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class NodeToken extends Model
{
    protected $fillable = [
        'node_id', 'token_hash', 'name', 'last_used_at', 'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'last_used_at' => 'datetime',
            'expires_at' => 'datetime',
        ];
    }

    public function node(): BelongsTo
    {
        return $this->belongsTo(Node::class);
    }
}
