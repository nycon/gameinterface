<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ImageServer extends Model
{
    protected $fillable = [
        'name', 'hostname', 'protocol', 'port', 'base_path', 'username',
        'password_encrypted', 'ssh_key_encrypted', 'public_url', 'is_active', 'status',
    ];

    protected $hidden = [
        'password_encrypted',
        'ssh_key_encrypted',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'port' => 'integer',
        ];
    }
}
