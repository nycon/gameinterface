<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ImageVersion extends Model
{
    protected $fillable = [
        'image_id', 'version', 'archive_name', 'archive_path', 'manifest_path',
        'list_path', 'checksum_path', 'size_bytes', 'checksum_sha256',
        'signature', 'is_latest',
    ];

    protected function casts(): array
    {
        return [
            'size_bytes' => 'integer',
            'is_latest' => 'boolean',
        ];
    }

    public function image(): BelongsTo
    {
        return $this->belongsTo(Image::class);
    }

    public function downloadLogs(): HasMany
    {
        return $this->hasMany(ImageDownloadLog::class);
    }
}
