<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Allocation extends Model
{
    protected $fillable = [
        'node_id', 'server_id', 'ip', 'port', 'protocol', 'notes',
    ];

    protected function casts(): array
    {
        return ['port' => 'integer'];
    }

    public function node(): BelongsTo
    {
        return $this->belongsTo(Node::class);
    }

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
