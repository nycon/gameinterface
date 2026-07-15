<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class Node extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'uuid', 'name', 'hostname', 'ip_address', 'agent_version', 'status',
        'cpu_cores', 'memory_mb', 'disk_gb', 'phpmyadmin_url',
        'mysql_admin_user', 'mysql_admin_password_encrypted',
        'last_heartbeat_at', 'meta',
    ];

    protected $hidden = [
        'mysql_admin_password_encrypted',
    ];

    protected function casts(): array
    {
        return [
            'last_heartbeat_at' => 'datetime',
            'meta' => 'array',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Node $node): void {
            $node->uuid ??= (string) Str::uuid();
        });
    }

    public function tokens(): HasMany
    {
        return $this->hasMany(NodeToken::class);
    }

    public function servers(): HasMany
    {
        return $this->hasMany(Server::class);
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(Allocation::class);
    }

    public function panelJobs(): HasMany
    {
        return $this->hasMany(PanelJob::class);
    }

    /**
     * phpMyAdmin-URL aus FQDN (Hostname mit Punkt) oder Fallback auf IP.
     */
    public static function preferredPhpmyadminUrl(string $hostname, string $ipAddress): string
    {
        $host = trim($hostname);
        if ($host !== '' && str_contains($host, '.') && filter_var($host, FILTER_VALIDATE_IP) === false) {
            return 'https://'.rtrim($host, '/').'/';
        }

        return 'https://'.rtrim($ipAddress, '/').'/';
    }
}
