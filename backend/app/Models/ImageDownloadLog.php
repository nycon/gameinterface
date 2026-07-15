<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ImageDownloadLog extends Model
{
    public $timestamps = false;

    protected $fillable = [
        'node_id', 'server_id', 'image_version_id', 'protocol', 'status',
        'bytes_downloaded', 'duration_ms', 'error', 'created_at',
    ];

    protected function casts(): array
    {
        return [
            'created_at' => 'datetime',
            'bytes_downloaded' => 'integer',
            'duration_ms' => 'integer',
        ];
    }

    public function node(): BelongsTo
    {
        return $this->belongsTo(Node::class);
    }

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }

    public function imageVersion(): BelongsTo
    {
        return $this->belongsTo(ImageVersion::class);
    }
}
