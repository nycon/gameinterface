<?php

namespace App\Services;

use App\Models\ImageServer;
use Illuminate\Support\Facades\Crypt;

class EncryptionService
{
    public function encrypt(?string $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        return Crypt::encryptString($value);
    }

    public function decrypt(?string $value): ?string
    {
        if ($value === null || $value === '') {
            return null;
        }

        return Crypt::decryptString($value);
    }
}
