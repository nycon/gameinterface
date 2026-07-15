<?php

namespace App\Http\Controllers\Api\Admin;

use App\Http\Controllers\Controller;
use App\Models\ImageServer;
use App\Services\AuditLogger;
use App\Services\DeployTokenService;
use App\Services\EncryptionService;
use App\Services\ImageServerConnectionTester;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ImageServerController extends Controller
{
    public function __construct(
        private readonly EncryptionService $encryption,
        private readonly ImageServerConnectionTester $tester,
        private readonly DeployTokenService $deployTokens,
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
            'hostname' => ['nullable', 'string', 'max:255'],
            'protocol' => ['nullable', 'in:sftp,ftps,ftp'],
            'port' => ['nullable', 'integer', 'min:1', 'max:65535'],
            'base_path' => ['nullable', 'string'],
            'username' => ['nullable', 'string'],
            'password' => ['nullable', 'string'],
            'ssh_key' => ['nullable', 'string'],
            'public_url' => ['nullable', 'url'],
            'is_active' => ['boolean'],
            'mode' => ['nullable', 'in:deploy,manual'],
        ]);

        $mode = $data['mode'] ?? ((! empty($data['hostname']) && ! empty($data['username'])) ? 'manual' : 'deploy');

        if ($mode === 'deploy') {
            $server = ImageServer::query()->create([
                'name' => $data['name'],
                'hostname' => $data['hostname'] ?? 'pending',
                'protocol' => $data['protocol'] ?? 'sftp',
                'port' => $data['port'] ?? 22,
                'base_path' => $data['base_path'] ?? '/images',
                'username' => $data['username'] ?? 'gamepanel-images',
                'password_encrypted' => null,
                'ssh_key_encrypted' => null,
                'public_url' => $data['public_url'] ?? null,
                'is_active' => false,
                'status' => 'pending',
            ]);

            $deploy = $this->deployTokens->createFor(
                $server,
                DeployTokenService::PURPOSE_IMAGE_SERVER,
                $request->user(),
            );

            $this->audit->log('image_server.created', $server);

            return response()->json([
                'image_server' => $server,
                'deploy_token' => $deploy['token'],
                'install_command' => $deploy['install_command'],
            ], 201);
        }

        $server = ImageServer::query()->create([
            'name' => $data['name'],
            'hostname' => $data['hostname'],
            'protocol' => $data['protocol'] ?? 'sftp',
            'port' => $data['port'] ?? 22,
            'base_path' => $data['base_path'] ?? '/images',
            'username' => $data['username'],
            'password_encrypted' => $this->encryption->encrypt($data['password'] ?? null),
            'ssh_key_encrypted' => $this->encryption->encrypt($data['ssh_key'] ?? null),
            'public_url' => $data['public_url'] ?? null,
            'is_active' => $data['is_active'] ?? true,
            'status' => 'ready',
        ]);

        $this->audit->log('image_server.created', $server);

        return response()->json([
            'image_server' => $server,
        ], 201);
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
            'status' => ['sometimes', 'in:pending,ready,error'],
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

    public function createDeployToken(Request $request, ImageServer $imageServer): JsonResponse
    {
        $deploy = $this->deployTokens->createFor(
            $imageServer,
            DeployTokenService::PURPOSE_IMAGE_SERVER,
            $request->user(),
        );
        $imageServer->update(['status' => 'pending', 'is_active' => false]);
        $this->audit->log('image_server.deploy_token_created', $imageServer);

        return response()->json([
            'deploy_token' => $deploy['token'],
            'install_command' => $deploy['install_command'],
        ], 201);
    }
}
