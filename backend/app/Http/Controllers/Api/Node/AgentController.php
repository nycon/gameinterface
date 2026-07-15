<?php

namespace App\Http\Controllers\Api\Node;

use App\Events\ServerOutputBroadcast;
use App\Http\Controllers\Controller;
use App\Models\Backup;
use App\Models\ImageServer;
use App\Models\Node;
use App\Models\PanelJob;
use App\Models\Server;
use App\Models\ServerEvent;
use App\Models\Setting;
use App\Services\ImageServerConnectionTester;
use App\Services\NodeAuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;

class AgentController extends Controller
{
    public function register(Request $request, NodeAuthService $nodeAuth): JsonResponse
    {
        $key = 'node-register:'.$request->ip();
        if (RateLimiter::tooManyAttempts($key, 10)) {
            return response()->json(['message' => 'Too many registration attempts'], 429);
        }
        RateLimiter::hit($key, 60);

        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'hostname' => ['required', 'string', 'max:255'],
            'ip_address' => ['required', 'ip'],
            'agent_version' => ['nullable', 'string'],
            'cpu_cores' => ['nullable', 'integer'],
            'memory_mb' => ['nullable', 'integer'],
            'disk_gb' => ['nullable', 'integer'],
            'setup_token' => ['nullable', 'string'],
            'node_uuid' => ['nullable', 'uuid'],
        ]);

        $expected = Setting::getValue('security.node_setup_token');
        if (filled($expected)) {
            if (! hash_equals((string) $expected, (string) ($data['setup_token'] ?? ''))) {
                return response()->json(['message' => 'Invalid setup token'], 403);
            }
        }

        if (! empty($data['node_uuid'])) {
            $node = Node::query()->where('uuid', $data['node_uuid'])->firstOrFail();
            $node->update(collect($data)->except(['setup_token', 'node_uuid'])->all() + [
                'status' => 'online',
                'last_heartbeat_at' => now(),
            ]);
        } else {
            $node = Node::query()->create(collect($data)->except(['setup_token', 'node_uuid'])->all() + [
                'status' => 'online',
                'last_heartbeat_at' => now(),
            ]);
        }

        $token = $nodeAuth->createToken($node, 'agent');

        return response()->json([
            'node' => $node,
            'token' => $token['token'],
        ], 201);
    }

    public function heartbeat(Request $request): JsonResponse
    {
        /** @var Node $node */
        $node = $request->attributes->get('node');

        $data = $request->validate([
            'agent_version' => ['nullable', 'string'],
            'cpu_cores' => ['nullable', 'integer'],
            'memory_mb' => ['nullable', 'integer'],
            'disk_gb' => ['nullable', 'integer'],
            'meta' => ['nullable', 'array'],
        ]);

        $node->update($data + [
            'status' => 'online',
            'last_heartbeat_at' => now(),
        ]);

        return response()->json(['ok' => true, 'server_time' => now()->toIso8601String()]);
    }

    public function jobs(Request $request): JsonResponse
    {
        /** @var Node $node */
        $node = $request->attributes->get('node');

		$jobs = PanelJob::query()
            ->where('node_id', $node->id)
            ->where('status', 'pending')
            ->orderByRaw("CASE
                WHEN type LIKE '%.files.%' THEN 0
                WHEN type LIKE '%.console.%' THEN 0
                WHEN type LIKE '%.ftp.%' THEN 1
                WHEN type LIKE '%.database.%' THEN 1
                WHEN type = 'server.diagnostics' THEN 1
                ELSE 2
            END")
            ->orderBy('id')
            ->limit(20)
            ->get();

        foreach ($jobs as $job) {
            $job->update([
                'status' => 'running',
                'started_at' => now(),
            ]);
        }

        return response()->json(['jobs' => $jobs]);
    }

    public function jobStatus(Request $request, string $uuid): JsonResponse
    {
        /** @var Node $node */
        $node = $request->attributes->get('node');

        $job = PanelJob::query()
            ->where('uuid', $uuid)
            ->where('node_id', $node->id)
            ->firstOrFail();

        $data = $request->validate([
            'status' => ['required', 'in:running,completed,failed'],
            'progress' => ['nullable', 'integer', 'min:0', 'max:100'],
            'result' => ['nullable', 'array'],
            'error' => ['nullable', 'string'],
            'server_status' => ['nullable', 'string'],
        ]);

        $job->update([
            'status' => $data['status'],
            'progress' => $data['progress'] ?? $job->progress,
            'result' => $data['result'] ?? $job->result,
            'error' => $data['error'] ?? null,
            'finished_at' => in_array($data['status'], ['completed', 'failed'], true) ? now() : null,
        ]);

        if ($job->server_id && ! empty($data['server_status'])) {
            Server::query()->whereKey($job->server_id)->update(['status' => $data['server_status']]);
        }

        if ($data['status'] === 'completed') {
            $this->syncBackupFromJob($job->fresh(), $data['result'] ?? []);
        }

        return response()->json(['job' => $job->fresh()]);
    }

    private function syncBackupFromJob(PanelJob $job, array $result): void
    {
        if (! $job->server_id) {
            return;
        }

        if ($job->type === 'server.backup' && ! empty($result['path'])) {
            $pending = Backup::query()
                ->where('server_id', $job->server_id)
                ->where('status', 'pending')
                ->where('name', (string) ($job->payload['name'] ?? ''))
                ->latest('id')
                ->first();

            $attrs = [
                'uuid' => (string) ($result['uuid'] ?? Str::uuid()),
                'name' => (string) ($job->payload['name'] ?? basename((string) $result['path'])),
                'path' => (string) $result['path'],
                'size_bytes' => (int) ($result['size_bytes'] ?? 0),
                'checksum_sha256' => $result['checksum_sha256'] ?? null,
                'status' => 'completed',
            ];

            if ($pending) {
                $pending->update($attrs);
            } else {
                Backup::query()->create($attrs + ['server_id' => $job->server_id]);
            }
        }

        if ($job->type === 'server.restore' && ! empty($result['backup_uuid'])) {
            Backup::query()
                ->where('uuid', $result['backup_uuid'])
                ->where('server_id', $job->server_id)
                ->update(['status' => 'restored']);
        }
    }

    public function metrics(Request $request): JsonResponse
    {
        /** @var Node $node */
        $node = $request->attributes->get('node');

        $data = $request->validate([
            'meta' => ['nullable', 'array'],
            'servers' => ['nullable', 'array'],
        ]);

        $meta = array_merge($node->meta ?? [], [
            'metrics' => $data['meta'] ?? [],
            'metrics_at' => now()->toIso8601String(),
        ]);

        $node->update(['meta' => $meta]);

        return response()->json(['ok' => true]);
    }

    public function events(Request $request): JsonResponse
    {
        $data = $request->validate([
            'server_id' => ['required', 'exists:servers,id'],
            'type' => ['required', 'string'],
            'message' => ['required', 'string'],
            'meta' => ['nullable', 'array'],
        ]);

        $event = ServerEvent::query()->create($data);

        if (in_array($event->type, ['console.output', 'console.history', 'server.log'], true)) {
            broadcast(new ServerOutputBroadcast($event));
        }

        return response()->json(['event' => $event], 201);
    }

    public function imageServerConfig(ImageServerConnectionTester $tester): JsonResponse
    {
        $server = ImageServer::query()->where('is_active', true)->latest()->first();

        if (! $server) {
            return response()->json(['message' => 'No active image server'], 404);
        }

        return response()->json([
            'image_server' => $tester->credentialsForAgent($server),
        ]);
    }
}
