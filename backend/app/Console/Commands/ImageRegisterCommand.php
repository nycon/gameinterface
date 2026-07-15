<?php

namespace App\Console\Commands;

use App\Models\GameTemplate;
use App\Models\Image;
use App\Models\ImageVersion;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

class ImageRegisterCommand extends Command
{
    protected $signature = 'gamepanel:image-register
        {slug : Image/Template-Slug (z.B. cs2)}
        {version : Version (z.B. 1.0.0)}
        {--name= : Anzeigename}
        {--sha256= : SHA256 des Archives (64 Hex)}
        {--size=0 : Größe in Bytes}
        {--template= : Template-Slug falls abweichend}';

    protected $description = 'Image + Version im Panel registrieren (nach gp-image build)';

    public function handle(): int
    {
        $slug = Str::slug((string) $this->argument('slug'));
        $version = (string) $this->argument('version');
        $sha = strtolower((string) ($this->option('sha256') ?: ''));
        $size = (int) $this->option('size');

        if ($sha === '' || ! preg_match('/^[a-f0-9]{64}$/', $sha)) {
            $this->error('--sha256=... (64 Hex) ist Pflicht. Nach dem Build: cat /srv/gamepanel-images/games/'.$slug.'/versions/'.$version.'/'.$slug.'-'.$version.'.sha256');

            return self::FAILURE;
        }

        $templateSlug = $this->option('template') ?: $slug;
        $template = GameTemplate::query()->where('slug', $templateSlug)->first();

        $base = "{$slug}-{$version}";
        $dir = "games/{$slug}/versions/{$version}";

        $image = Image::query()->firstOrCreate(
            ['slug' => $slug],
            [
                'name' => $this->option('name') ?: Str::headline($slug),
                'game_template_id' => $template?->id,
                'description' => null,
            ]
        );

        if ($template && $image->game_template_id !== $template->id) {
            $image->update(['game_template_id' => $template->id]);
        }

        $image->versions()->where('is_latest', true)->update(['is_latest' => false]);

        $ver = ImageVersion::query()->updateOrCreate(
            ['image_id' => $image->id, 'version' => $version],
            [
                'archive_name' => "{$base}.tar.zst",
                'archive_path' => "{$dir}/{$base}.tar.zst",
                'manifest_path' => "{$dir}/{$base}.manifest.json",
                'list_path' => "{$dir}/{$base}.lst",
                'checksum_path' => "{$dir}/{$base}.sha256",
                'size_bytes' => max(0, $size),
                'checksum_sha256' => $sha,
                'is_latest' => true,
            ]
        );

        $this->info("Registriert: {$image->slug}@{$ver->version} (image_id={$image->id}, version_id={$ver->id})");
        $this->line("Pfad: {$dir}/{$base}.tar.zst");

        return self::SUCCESS;
    }
}
