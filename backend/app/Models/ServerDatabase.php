<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ServerDatabase extends Model
{
    protected $table = 'server_databases';

    protected $fillable = [
        'server_id', 'name', 'username', 'password_encrypted',
        'host', 'port', 'engine',
    ];

    protected $hidden = ['password_encrypted'];

    protected function casts(): array
    {
        return ['port' => 'integer'];
    }

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
