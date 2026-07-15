<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

class Server extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'uuid', 'name', 'user_id', 'node_id', 'game_template_id', 'image_version_id',
        'status', 'linux_user', 'install_path', 'cpu_quota', 'memory_max',
        'startup_command', 'meta',
    ];

    protected function casts(): array
    {
        return [
            'meta' => 'array',
        ];
    }

    protected static function booted(): void
    {
        static::creating(function (Server $server): void {
            $server->uuid ??= (string) Str::uuid();
        });
    }

    public function owner(): BelongsTo
    {
        return $this->belongsTo(User::class, 'user_id');
    }

    public function node(): BelongsTo
    {
        return $this->belongsTo(Node::class);
    }

    public function template(): BelongsTo
    {
        return $this->belongsTo(GameTemplate::class, 'game_template_id');
    }

    public function imageVersion(): BelongsTo
    {
        return $this->belongsTo(ImageVersion::class);
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(Allocation::class);
    }

    public function backups(): HasMany
    {
        return $this->hasMany(Backup::class);
    }

    public function databases(): HasMany
    {
        return $this->hasMany(ServerDatabase::class);
    }

    public function variables(): HasMany
    {
        return $this->hasMany(ServerVariable::class);
    }

    public function events(): HasMany
    {
        return $this->hasMany(ServerEvent::class);
    }

    public function panelJobs(): HasMany
    {
        return $this->hasMany(PanelJob::class);
    }

    public function ftpAccounts(): HasMany
    {
        return $this->hasMany(FtpAccount::class);
    }
}
