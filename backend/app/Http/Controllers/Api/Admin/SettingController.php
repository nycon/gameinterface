<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SettingController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(Setting::query()->orderBy('key')->get());
    }

    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'settings' => ['required', 'array'],
            'settings.*.key' => ['required', 'string'],
            'settings.*.value' => ['nullable'],
        ]);

        foreach ($data['settings'] as $row) {
            Setting::setValue($row['key'], $row['value']);
        }

        return response()->json(Setting::query()->orderBy('key')->get());
    }
}
