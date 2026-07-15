<?php

namespace App\Http\Controllers\Api\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\AuditLogger;
use App\Services\EncryptionService;
use App\Services\TotpService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly TotpService $totp,
        private readonly EncryptionService $encryption,
    ) {}

    public function login(Request $request): JsonResponse
    {
        $credentials = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::query()->where('email', $credentials['email'])->first();

        if (! $user || ! Hash::check($credentials['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => ['Invalid credentials.'],
            ]);
        }

        if ($user->two_factor_confirmed_at) {
            $challenge = Str::random(64);
            Cache::put('2fa:'.$challenge, $user->id, now()->addMinutes(5));

            return response()->json([
                'two_factor' => true,
                'challenge' => $challenge,
            ]);
        }

        return $this->issueToken($user);
    }

    public function twoFactorChallenge(Request $request): JsonResponse
    {
        $data = $request->validate([
            'challenge' => ['required', 'string'],
            'code' => ['required', 'string'],
        ]);

        $userId = Cache::pull('2fa:'.$data['challenge']);
        if (! $userId) {
            throw ValidationException::withMessages(['challenge' => ['Expired or invalid challenge.']]);
        }

        $user = User::query()->findOrFail($userId);
        $secret = $this->encryption->decrypt($user->two_factor_secret);

        $valid = $this->totp->verify($secret, $data['code']);
        if (! $valid) {
            $codes = json_decode($user->two_factor_recovery_codes ?? '[]', true) ?: [];
            $idx = array_search($data['code'], $codes, true);
            if ($idx === false) {
                throw ValidationException::withMessages(['code' => ['Invalid code.']]);
            }
            unset($codes[$idx]);
            $user->update(['two_factor_recovery_codes' => json_encode(array_values($codes))]);
        }

        return $this->issueToken($user);
    }

    public function me(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'is_admin' => (bool) $user->is_admin,
            'locale' => $user->locale,
            'roles' => $user->getRoleNames(),
            'two_factor_enabled' => (bool) $user->two_factor_confirmed_at,
            'reseller_id' => $user->reseller_id,
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()?->delete();
        $this->audit->log('auth.logout', $request->user());

        return response()->json(['message' => 'Logged out']);
    }

    public function enableTwoFactor(Request $request): JsonResponse
    {
        $user = $request->user();
        $secret = $this->totp->generateSecret();
        $recovery = $this->totp->recoveryCodes();

        $user->update([
            'two_factor_secret' => $this->encryption->encrypt($secret),
            'two_factor_recovery_codes' => json_encode($recovery),
            'two_factor_confirmed_at' => null,
        ]);

        return response()->json([
            'secret' => $secret,
            'otpauth_url' => $this->totp->provisioningUri($secret, $user->email),
            'recovery_codes' => $recovery,
        ]);
    }

    public function confirmTwoFactor(Request $request): JsonResponse
    {
        $data = $request->validate(['code' => ['required', 'string']]);
        $user = $request->user();
        abort_unless($user->two_factor_secret, 422);

        $secret = $this->encryption->decrypt($user->two_factor_secret);
        if (! $this->totp->verify($secret, $data['code'])) {
            throw ValidationException::withMessages(['code' => ['Invalid code.']]);
        }

        $user->update(['two_factor_confirmed_at' => now()]);
        $this->audit->log('auth.2fa.enabled', $user);

        return response()->json(['two_factor_enabled' => true]);
    }

    public function disableTwoFactor(Request $request): JsonResponse
    {
        $data = $request->validate(['password' => ['required', 'string']]);
        $user = $request->user();

        if (! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['password' => ['Invalid password.']]);
        }

        $user->update([
            'two_factor_secret' => null,
            'two_factor_recovery_codes' => null,
            'two_factor_confirmed_at' => null,
        ]);
        $this->audit->log('auth.2fa.disabled', $user);

        return response()->json(['two_factor_enabled' => false]);
    }

    private function issueToken(User $user): JsonResponse
    {
        Auth::login($user);
        $token = $user->createToken('panel')->plainTextToken;
        $this->audit->log('auth.login', $user);

        return response()->json([
            'token' => $token,
            'token_type' => 'Bearer',
            'user' => [
                'id' => $user->id,
                'name' => $user->name,
                'email' => $user->email,
                'is_admin' => (bool) $user->is_admin,
                'roles' => $user->getRoleNames(),
                'two_factor_enabled' => (bool) $user->two_factor_confirmed_at,
            ],
        ]);
    }
}
