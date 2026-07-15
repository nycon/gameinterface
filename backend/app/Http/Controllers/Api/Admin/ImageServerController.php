<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\ImageServer;
use App\Services\AuditLogger;
use App\Services\EncryptionService;
use App\Services\ImageServerConnectionTester;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ImageServerController extends Controller
{
    public function __construct(
        private readonly EncryptionService $encryption,
        private readonly ImageServerConnectionTester $tester,
        private readonly AuditLogger $audit,
    ) {}

    public function index(): JsonResponse
    {
        return response()->json(ImageServer::query()->latest()->paginate(25));
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'hostname' => ['required', 'string', 'max:255'],
            'protocol' => ['required', 'in:sftp,ftps,ftp'],
            'port' => ['required', 'integer', 'min:1', 'max:65535'],
            'base_path' => ['required', 'string'],
            'username' => ['required', 'string'],
            'password' => ['nullable', 'string'],
            'ssh_key' => ['nullable', 'string'],
            'public_url' => ['nullable', 'url'],
            'is_active' => ['boolean'],
        ]);

        if (($data['protocol'] ?? '') === 'ftp') {
            // Warn in response but allow for internal networks
        }

        $server = ImageServer::query()->create([
            'name' => $data['name'],
            'hostname' => $data['hostname'],
            'protocol' => $data['protocol'],
            'port' => $data['port'],
            'base_path' => $data['base_path'],
            'username' => $data['username'],
            'password_encrypted' => $this->encryption->encrypt($data['password'] ?? null),
            'ssh_key_encrypted' => $this->encryption->encrypt($data['ssh_key'] ?? null),
            'public_url' => $data['public_url'] ?? null,
            'is_active' => $data['is_active'] ?? true,
        ]);

        $this->audit->log('image_server.created', $server);

        return response()->json($server, 201);
    }

    public function show(ImageServer $imageServer): JsonResponse
    {
        return response()->json($imageServer);
    }

    public function update(Request $request, ImageServer $imageServer): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:255'],
            'hostname' => ['sometimes', 'string', 'max:255'],
            'protocol' => ['sometimes', 'in:sftp,ftps,ftp'],
            'port' => ['sometimes', 'integer'],
            'base_path' => ['sometimes', 'string'],
            'username' => ['sometimes', 'string'],
            'password' => ['nullable', 'string'],
            'ssh_key' => ['nullable', 'string'],
            'public_url' => ['nullable', 'url'],
            'is_active' => ['boolean'],
        ]);

        $payload = collect($data)->except(['password', 'ssh_key'])->all();
        if (array_key_exists('password', $data)) {
            $payload['password_encrypted'] = $this->encryption->encrypt($data['password']);
        }
        if (array_key_exists('ssh_key', $data)) {
            $payload['ssh_key_encrypted'] = $this->encryption->encrypt($data['ssh_key']);
        }

        $imageServer->update($payload);
        $this->audit->log('image_server.updated', $imageServer);

        return response()->json($imageServer);
    }

    public function destroy(ImageServer $imageServer): JsonResponse
    {
        $imageServer->delete();
        $this->audit->log('image_server.deleted', $imageServer);

        return response()->json(null, 204);
    }

    public function test(ImageServer $imageServer): JsonResponse
    {
        $result = $this->tester->test($imageServer);
        $this->audit->log('image_server.tested', $imageServer, $result);

        return response()->json($result, $result['ok'] ? 200 : 422);
    }
}
