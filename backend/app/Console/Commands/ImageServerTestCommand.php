<?php

namespace App\Console\Commands;

use App\Models\ImageServer;
use App\Services\ImageServerConnectionTester;
use Illuminate\Console\Command;

class ImageServerTestCommand extends Command
{
    protected $signature = 'gamepanel:image-server-test {id? : Image server ID}';

    protected $description = 'Validate image server configuration';

    public function handle(ImageServerConnectionTester $tester): int
    {
        $server = $this->argument('id')
            ? ImageServer::query()->findOrFail($this->argument('id'))
            : ImageServer::query()->where('is_active', true)->latest()->first();

        if (! $server) {
            $this->error('No image server found');

            return self::FAILURE;
        }

        $result = $tester->test($server);
        $this->line(json_encode($result, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

        return $result['ok'] ? self::SUCCESS : self::FAILURE;
    }
}
