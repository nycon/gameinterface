<?php

namespace App\Console\Commands;

use App\Models\Setting;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

class SetupTokenCreateCommand extends Command
{
    protected $signature = 'gamepanel:setup-token-create
        {--show : Nur vorhandenen Token anzeigen}';

    protected $description = 'Create or rotate the node setup token';

    public function handle(): int
    {
        if ($this->option('show')) {
            $existing = Setting::getValue('security.node_setup_token');
            if (! $existing) {
                $this->error('Kein Setup-Token vorhanden');

                return self::FAILURE;
            }
            $this->line($existing);

            return self::SUCCESS;
        }

        $token = 'gps_'.Str::random(40);
        Setting::setValue('security.node_setup_token', $token);
        Setting::setValue('security.node_setup_token_created_at', now()->toIso8601String());

        $this->info('Setup-Token erzeugt (einmalig speichern):');
        $this->line($token);

        return self::SUCCESS;
    }
}
