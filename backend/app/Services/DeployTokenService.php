<?php

namespace App\Services;

use App\Models\DeployToken;
use App\Models\ImageServer;
use App\Models\Node;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;
use InvalidArgumentException;

class DeployTokenService
{
    public const PURPOSE_NODE = 'node';

    public const PURPOSE_IMAGE_SERVER = 'image_server';

    /**
     * @return array{token: string, model: DeployToken, install_command: string}
     */
    public function createFor(Model $resource, string $purpose, ?User $creator = null, ?int $ttlHours = 72): array
    {
        $purpose = $this->normalizePurpose($purpose, $resource);

        // Invalidate unused previous tokens for this resource
        DeployToken::query()
            ->where('resource_type', $resource->getMorphClass())
            ->where('resource_id', $resource->getKey())
            ->whereNull('used_at')
            ->delete();

        $plain = 'gpd_'.Str::random(48);

        $model = DeployToken::query()->create([
            'token_hash' => hash('sha256', $plain),
            'purpose' => $purpose,
            'resource_type' => $resource->getMorphClass(),
            'resource_id' => $resource->getKey(),
            'expires_at' => $ttlHours ? now()->addHours($ttlHours) : null,
            'created_by' => $creator?->id,
        ]);

        return [
            'token' => $plain,
            'model' => $model,
            'install_command' => $this->installCommand($purpose, $plain),
        ];
    }

    public function findValid(string $plain, ?string $purpose = null): ?DeployToken
    {
        $token = DeployToken::query()
            ->where('token_hash', hash('sha256', $plain))
            ->first();

        if (! $token || $token->isUsed() || $token->isExpired()) {
            return null;
        }

        if ($purpose !== null && $token->purpose !== $purpose) {
            return null;
        }

        return $token;
    }

    public function consume(DeployToken $token): void
    {
        $token->forceFill(['used_at' => now()])->save();
    }

    public function installCommand(string $purpose, string $plainToken): string
    {
        $base = rtrim((string) config('app.url'), '/');
        $path = match ($purpose) {
            self::PURPOSE_NODE => "/install/node/{$plainToken}.sh",
            self::PURPOSE_IMAGE_SERVER => "/install/image-server/{$plainToken}.sh",
            default => throw new InvalidArgumentException("Unknown purpose: {$purpose}"),
        };

        return "curl -fsSL {$base}{$path} | sudo bash";
    }

    public function panelUrl(): string
    {
        return rtrim((string) config('app.url'), '/');
    }

    private function normalizePurpose(string $purpose, Model $resource): string
    {
        if ($purpose === self::PURPOSE_NODE && ! $resource instanceof Node) {
            throw new InvalidArgumentException('Node purpose requires Node model');
        }
        if ($purpose === self::PURPOSE_IMAGE_SERVER && ! $resource instanceof ImageServer) {
            throw new InvalidArgumentException('Image server purpose requires ImageServer model');
        }

        return $purpose;
    }
}
