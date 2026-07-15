<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Image extends Model
{
    protected $fillable = [
        'game_template_id', 'name', 'slug', 'description',
    ];

    public function template(): BelongsTo
    {
        return $this->belongsTo(GameTemplate::class, 'game_template_id');
    }

    public function versions(): HasMany
    {
        return $this->hasMany(ImageVersion::class);
    }

    public function latestVersion(): ?ImageVersion
    {
        return $this->versions()->where('is_latest', true)->first()
            ?? $this->versions()->latest('id')->first();
    }
}
