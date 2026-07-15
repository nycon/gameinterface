<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class Backup extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'server_id', 'uuid', 'name', 'path', 'size_bytes',
        'checksum_sha256', 'status', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
            'size_bytes' => 'integer',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Backup $backup): void {
            $backup->uuid ??= (string) Str::uuid();
            $backup->created_at ??= now();
        });
    }

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
