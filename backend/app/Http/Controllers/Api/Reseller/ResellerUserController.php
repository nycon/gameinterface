<?php

namespace App\Http\Controllers\Api\Reseller;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Spatie\Permission\Models\Role;

class ResellerUserController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();
        $query = User::query()->where('reseller_id', $user->id);

        if ($user->is_admin || $user->hasRole('admin')) {
            $query = User::query()->whereNotNull('reseller_id');
        }

        return response()->json($query->latest()->paginate(25));
    }

    public function store(Request $request): JsonResponse
    {
        $reseller = $request->user();
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'unique:users,email'],
            'password' => ['required', 'string', 'min:10'],
        ]);

        $customer = User::query()->create([
            'name' => $data['name'],
            'email' => $data['email'],
            'password' => $data['password'],
            'is_admin' => false,
            'reseller_id' => $reseller->id,
            'locale' => 'de',
        ]);

        $customer->syncRoles([Role::findOrCreate('customer', 'web')]);
        $this->audit->log('reseller.user.created', $customer);

        return response()->json($customer, 201);
    }
}
