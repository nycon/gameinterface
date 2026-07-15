<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\GameTemplate;
use App\Models\Image;
use App\Models\ImageVersion;
use App\Services\AuditLogger;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ImageController extends Controller
{
    public function __construct(private readonly AuditLogger $audit) {}

    public function index(): JsonResponse
    {
        return response()->json(
            Image::query()->with(['template:id,name,slug', 'versions'])->latest()->paginate(25)
        );
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'slug' => ['nullable', 'string', 'max:255', 'unique:images,slug'],
            'description' => ['nullable', 'string'],
            'game_template_id' => ['nullable', 'exists:game_templates,id'],
        ]);

        $data['slug'] ??= Str::slug($data['name']);
        $image = Image::query()->create($data);
        $this->audit->log('image.created', $image);

        return response()->json($image, 201);
    }

    public function show(Image $image): JsonResponse
    {
        return response()->json($image->load(['template', 'versions']));
    }

    public function storeVersion(Request $request, Image $image): JsonResponse
    {
        $data = $request->validate([
            'version' => ['required', 'string', 'max:64'],
            'archive_name' => ['required', 'string'],
            'archive_path' => ['required', 'string'],
            'manifest_path' => ['required', 'string'],
            'list_path' => ['required', 'string'],
            'checksum_path' => ['required', 'string'],
            'size_bytes' => ['required', 'integer', 'min:0'],
            'checksum_sha256' => ['required', 'string', 'size:64'],
            'signature' => ['nullable', 'string'],
            'is_latest' => ['boolean'],
        ]);

        if ($data['is_latest'] ?? false) {
            $image->versions()->update(['is_latest' => false]);
        }

        $version = $image->versions()->create($data);
        $this->audit->log('image.version_created', $image, ['version' => $version->version]);

        return response()->json($version, 201);
    }

    public function destroy(Image $image): JsonResponse
    {
        $image->delete();
        $this->audit->log('image.deleted', $image);

        return response()->json(null, 204);
    }
}
