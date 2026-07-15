<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('nodes', function (Blueprint $table) {
            $table->string('phpmyadmin_url')->nullable()->after('disk_gb');
            $table->string('mysql_admin_user', 64)->nullable()->after('phpmyadmin_url');
            $table->text('mysql_admin_password_encrypted')->nullable()->after('mysql_admin_user');
        });
    }

    public function down(): void
    {
        Schema::table('nodes', function (Blueprint $table) {
            $table->dropColumn(['phpmyadmin_url', 'mysql_admin_user', 'mysql_admin_password_encrypted']);
        });
    }
};
