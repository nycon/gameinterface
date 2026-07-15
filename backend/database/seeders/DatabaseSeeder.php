<?php

namespace Database\Seeders;

use App\Models\GameTemplate;
use App\Models\Setting;
use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\File;
use Spatie\Permission\Models\Role;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $adminRole = Role::findOrCreate('admin');
        $customerRole = Role::findOrCreate('customer');
        $resellerRole = Role::findOrCreate('reseller');

        $admin = User::query()->updateOrCreate(
            ['email' => 'admin@gamepanel.local'],
            [
                'name' => 'GamePanel Admin',
                'password' => 'ChangeMe!2026',
                'is_admin' => true,
                'locale' => 'de',
            ]
        );
        $admin->syncRoles([$adminRole]);

        $reseller = User::query()->updateOrCreate(
            ['email' => 'reseller@gamepanel.local'],
            [
                'name' => 'Demo Reseller',
                'password' => 'ChangeMe!2026',
                'is_admin' => false,
                'locale' => 'de',
            ]
        );
        $reseller->syncRoles([$resellerRole]);

        User::query()->updateOrCreate(
            ['email' => 'customer@gamepanel.local'],
            [
                'name' => 'Demo Customer',
                'password' => 'ChangeMe!2026',
                'is_admin' => false,
                'locale' => 'de',
                'reseller_id' => $reseller->id,
            ]
        )->syncRoles([$customerRole]);

        Setting::setValue('panel.name', 'GamePanel');
        Setting::setValue('panel.locale', 'de');
        Setting::setValue('security.require_sftp', '1');
        Setting::setValue('images.prefer_protocol', 'sftp');

        if (! Setting::getValue('security.node_setup_token')) {
            Setting::setValue('security.node_setup_token', 'gps_'.\Illuminate\Support\Str::random(40));
        }

        $templateDirs = array_filter([
            base_path('resources/game-templates'),
            base_path('../templates/games'),
            '/opt/gamepanel/templates/games',
        ], fn (string $dir) => File::isDirectory($dir));

        foreach ($templateDirs as $templatesPath) {
            foreach (File::files($templatesPath) as $file) {
                if ($file->getExtension() !== 'yaml' && $file->getExtension() !== 'yml') {
                    continue;
                }

                $yaml = File::get($file->getPathname());
                $slug = $file->getFilenameWithoutExtension();
                $name = ucfirst(str_replace('-', ' ', $slug));
                $type = 'steam';
                $steamAppId = null;

                if (preg_match('/^name:\s*"?([^"\n]+)"?/m', $yaml, $m)) {
                    $name = trim($m[1]);
                }
                if (preg_match('/^type:\s*"?([^"\n]+)"?/m', $yaml, $m)) {
                    $type = trim($m[1]);
                }
                if (preg_match('/steam_app_id:\s*"?([^"\n]+)"?/m', $yaml, $m)) {
                    $steamAppId = trim($m[1]);
                }

                GameTemplate::query()->updateOrCreate(
                    ['slug' => $slug],
                    [
                        'name' => $name,
                        'type' => $type,
                        'yaml_definition' => $yaml,
                        'steam_app_id' => $steamAppId,
                        'is_active' => true,
                    ]
                );
            }
        }
    }
}
