<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class PanelJob extends Model
{
    protected $fillable = [
        'uuid', 'type', 'status', 'payload', 'result', 'node_id', 'server_id',
        'progress', 'error', 'started_at', 'finished_at',
    ];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'result' => 'array',
            'progress' => 'integer',
            'started_at' => 'datetime',
            'finished_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (PanelJob $job): void {
            $job->uuid ??= (string) Str::uuid();
        });
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
