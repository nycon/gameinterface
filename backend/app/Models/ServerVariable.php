<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ServerVariable extends Model
{
    protected $fillable = ['server_id', 'key', 'value'];

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
