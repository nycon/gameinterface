<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;
use Spatie\Permission\Models\Role;

class UserController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        return response()->json(
            User::query()->with('roles')->latest()->paginate(25)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'unique:users,email'],
            'password' => ['required', 'string', 'min:10'],
            'is_admin' => ['boolean'],
            'role' => ['nullable', 'string', 'in:admin,customer,reseller'],
            'reseller_id' => ['nullable', 'exists:users,id'],
            'locale' => ['nullable', 'string', 'max:10'],
        ]);

        $role = $data['role'] ?? (($data['is_admin'] ?? false) ? 'admin' : 'customer');

        $user = User::query()->create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => $data['password'],
            'is_admin' => $role === 'admin' || ($data['is_admin'] ?? false),
            'reseller_id' => $data['reseller_id'] ?? null,
            'locale' => $data['locale'] ?? 'de',
        ]);

        $user->syncRoles([Role::findOrCreate($role, 'web')]);
        $this->audit->log('user.created', $user);

        return response()->json($user->load('roles'), 201);
    }

    public function show(User $user): JsonResponse
    {
        return response()->json($user->load(['roles', 'servers']));
    }

    public function update(Request $request, User $user): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'email' => ['sometimes', 'email', Rule::unique('users')->ignore($user->id)],
            'password' => ['nullable', 'string', 'min:10'],
            'is_admin' => ['boolean'],
            'role' => ['nullable', 'string', 'in:admin,customer,reseller'],
            'reseller_id' => ['nullable', 'exists:users,id'],
            'locale' => ['nullable', 'string', 'max:10'],
        ]);

        if (empty($data['password'])) {
            unset($data['password']);
        }

        if (! empty($data['role'])) {
            $user->syncRoles([Role::findOrCreate($data['role'], 'web')]);
            $data['is_admin'] = $data['role'] === 'admin';
        } elseif (array_key_exists('is_admin', $data)) {
            $user->syncRoles([Role::findOrCreate($data['is_admin'] ? 'admin' : 'customer', 'web')]);
        }

        $user->update($data);
        $this->audit->log('user.updated', $user);

        return response()->json($user->fresh()->load('roles'));
    }

    public function destroy(User $user): JsonResponse
    {
        if ($user->id === request()->user()?->id) {
            return response()->json(['message' => 'Eigenen Account nicht löschen'], 422);
        }

        $user->delete();
        $this->audit->log('user.deleted', $user);

        return response()->json(null, 204);
    }
}
