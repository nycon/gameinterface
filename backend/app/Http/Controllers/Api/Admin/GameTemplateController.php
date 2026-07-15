<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\GameTemplate;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class GameTemplateController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        return response()->json(
            GameTemplate::query()->latest()->paginate(50)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'slug' => ['nullable', 'string', 'max:255', 'unique:game_templates,slug'],
            'type' => ['required', 'in:steam,minecraft,url,custom'],
            'yaml_definition' => ['required', 'string'],
            'steam_app_id' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        $data['slug'] ??= Str::slug($data['name']);
        $template = GameTemplate::query()->create($data);
        $this->audit->log('template.created', $template);

        return response()->json($template, 201);
    }

    public function show(GameTemplate $template): JsonResponse
    {
        return response()->json($template);
    }

    public function update(Request $request, GameTemplate $template): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'type' => ['sometimes', 'in:steam,minecraft,url,custom'],
            'yaml_definition' => ['sometimes', 'string'],
            'steam_app_id' => ['nullable', 'string'],
            'is_active' => ['boolean'],
        ]);

        $template->update($data);
        $this->audit->log('template.updated', $template);

        return response()->json($template);
    }

    public function destroy(GameTemplate $template): JsonResponse
    {
        $template->delete();
        $this->audit->log('template.deleted', $template);

        return response()->json(null, 204);
    }
}
