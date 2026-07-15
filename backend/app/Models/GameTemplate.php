<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class GameTemplate extends Model
{
    protected $fillable = [
        'name', 'slug', 'type', 'yaml_definition', 'steam_app_id', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
        ];
    }

    public function images(): HasMany
    {
        return $this->hasMany(Image::class);
    }

    public function servers(): HasMany
    {
        return $this->hasMany(Server::class);
    }
}
