<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FtpAccount extends Model
{
    protected $fillable = [
        'server_id', 'username', 'password_encrypted', 'home_path',
    ];

    protected $hidden = ['password_encrypted'];

    public function server(): BelongsTo
    {
        return $this->belongsTo(Server::class);
    }
}
