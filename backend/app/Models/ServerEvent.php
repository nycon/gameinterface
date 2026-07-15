<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ServerEvent extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'server_id', 'type', 'message', 'meta', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'meta' => 'array',
            'created_at' => 'datetime',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (ServerEvent $event): void {
            $event->created_at ??= now();
        });
    }

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
