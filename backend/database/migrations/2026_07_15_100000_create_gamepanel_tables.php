<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->boolean('is_admin')->default(false)->after('password');
            $table->string('locale', 10)->nullable()->after('is_admin');
        });

        Schema::create('nodes', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid')->unique();
            $table->string('name');
            $table->string('hostname');
            $table->string('ip_address', 45);
            $table->string('agent_version')->nullable();
            $table->string('status', 32)->default('offline')->index();
            $table->unsignedInteger('cpu_cores')->nullable();
            $table->unsignedBigInteger('memory_mb')->nullable();
            $table->unsignedBigInteger('disk_gb')->nullable();
            $table->timestamp('last_heartbeat_at')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('node_tokens', function (Blueprint $table) {
            $table->id();
            $table->foreignId('node_id')->constrained()->cascadeOnDelete();
            $table->string('token_hash', 64)->unique();
            $table->string('name')->default('default');
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();
        });

        Schema::create('image_servers', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('hostname');
            $table->string('protocol', 16)->default('sftp');
            $table->unsignedSmallInteger('port')->default(22);
            $table->string('base_path')->default('/games');
            $table->string('username');
            $table->text('password_encrypted')->nullable();
            $table->text('ssh_key_encrypted')->nullable();
            $table->string('public_url')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('game_templates', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('slug')->unique();
            $table->string('type', 32)->default('steam');
            $table->longText('yaml_definition');
            $table->string('steam_app_id')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('images', function (Blueprint $table) {
            $table->id();
            $table->foreignId('game_template_id')->nullable()->constrained()->nullOnDelete();
            $table->string('name');
            $table->string('slug')->unique();
            $table->text('description')->nullable();
            $table->timestamps();
        });

        Schema::create('image_versions', function (Blueprint $table) {
            $table->id();
            $table->foreignId('image_id')->constrained()->cascadeOnDelete();
            $table->string('version');
            $table->string('archive_name');
            $table->string('archive_path');
            $table->string('manifest_path');
            $table->string('list_path');
            $table->string('checksum_path');
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->string('checksum_sha256', 64);
            $table->text('signature')->nullable();
            $table->boolean('is_latest')->default(false);
            $table->timestamps();
            $table->unique(['image_id', 'version']);
        });

        Schema::create('servers', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid')->unique();
            $table->string('name');
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('node_id')->constrained()->cascadeOnDelete();
            $table->foreignId('game_template_id')->constrained()->restrictOnDelete();
            $table->foreignId('image_version_id')->nullable()->constrained()->nullOnDelete();
            $table->string('status', 32)->default('installing')->index();
            $table->string('linux_user')->nullable();
            $table->string('install_path')->nullable();
            $table->string('cpu_quota')->nullable();
            $table->string('memory_max')->nullable();
            $table->text('startup_command')->nullable();
            $table->json('meta')->nullable();
            $table->timestamps();
            $table->softDeletes();
        });

        Schema::create('image_download_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('node_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('server_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('image_version_id')->nullable()->constrained()->nullOnDelete();
            $table->string('protocol', 16);
            $table->string('status', 32);
            $table->unsignedBigInteger('bytes_downloaded')->default(0);
            $table->unsignedInteger('duration_ms')->nullable();
            $table->text('error')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('allocations', function (Blueprint $table) {
            $table->id();
            $table->foreignId('node_id')->constrained()->cascadeOnDelete();
            $table->foreignId('server_id')->nullable()->constrained()->nullOnDelete();
            $table->string('ip', 45);
            $table->unsignedInteger('port');
            $table->string('protocol', 8)->default('udp');
            $table->string('notes')->nullable();
            $table->timestamps();
            $table->unique(['node_id', 'ip', 'port', 'protocol']);
        });

        Schema::create('backups', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained()->cascadeOnDelete();
            $table->uuid('uuid')->unique();
            $table->string('name');
            $table->string('path');
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->string('checksum_sha256', 64)->nullable();
            $table->string('status', 32)->default('pending');
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('server_databases', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('username');
            $table->text('password_encrypted');
            $table->string('host')->default('127.0.0.1');
            $table->unsignedSmallInteger('port')->default(3306);
            $table->string('engine', 16)->default('mariadb');
            $table->timestamps();
        });

        Schema::create('panel_jobs', function (Blueprint $table) {
            $table->id();
            $table->uuid('uuid')->unique();
            $table->string('type');
            $table->string('status', 32)->default('pending')->index();
            $table->json('payload');
            $table->json('result')->nullable();
            $table->foreignId('node_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('server_id')->nullable()->constrained()->nullOnDelete();
            $table->unsignedTinyInteger('progress')->default(0);
            $table->text('error')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();
        });

        Schema::create('audit_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('action');
            $table->string('auditable_type')->nullable();
            $table->unsignedBigInteger('auditable_id')->nullable();
            $table->string('ip_address', 45)->nullable();
            $table->text('user_agent')->nullable();
            $table->json('meta')->nullable();
            $table->timestamp('created_at')->useCurrent();
            $table->index(['auditable_type', 'auditable_id']);
        });

        Schema::create('ftp_accounts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained()->cascadeOnDelete();
            $table->string('username');
            $table->text('password_encrypted');
            $table->string('home_path');
            $table->timestamps();
        });

        Schema::create('settings', function (Blueprint $table) {
            $table->id();
            $table->string('key')->unique();
            $table->text('value')->nullable();
            $table->timestamps();
        });

        Schema::create('server_variables', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained()->cascadeOnDelete();
            $table->string('key');
            $table->text('value')->nullable();
            $table->timestamps();
            $table->unique(['server_id', 'key']);
        });

        Schema::create('server_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('server_id')->constrained()->cascadeOnDelete();
            $table->string('type');
            $table->text('message');
            $table->json('meta')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('server_events');
        Schema::dropIfExists('server_variables');
        Schema::dropIfExists('settings');
        Schema::dropIfExists('ftp_accounts');
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('panel_jobs');
        Schema::dropIfExists('server_databases');
        Schema::dropIfExists('backups');
        Schema::dropIfExists('allocations');
        Schema::dropIfExists('image_download_logs');
        Schema::dropIfExists('servers');
        Schema::dropIfExists('image_versions');
        Schema::dropIfExists('images');
        Schema::dropIfExists('game_templates');
        Schema::dropIfExists('image_servers');
        Schema::dropIfExists('node_tokens');
        Schema::dropIfExists('nodes');

        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['is_admin', 'locale']);
        });
    }
};
