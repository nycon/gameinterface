<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('deploy_tokens', function (Blueprint $table) {
            $table->id();
            $table->string('token_hash', 64)->unique();
            $table->string('purpose', 32);
            $table->string('resource_type');
            $table->unsignedBigInteger('resource_id');
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('used_at')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['purpose', 'resource_type', 'resource_id']);
        });

        Schema::table('image_servers', function (Blueprint $table) {
            $table->string('status', 32)->default('ready')->after('is_active')->index();
        });
    }

    public function down(): void
    {
        Schema::table('image_servers', function (Blueprint $table) {
            $table->dropColumn('status');
        });

        Schema::dropIfExists('deploy_tokens');
    }
};
