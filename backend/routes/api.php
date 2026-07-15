<?php

use App\Http\Controllers\Api\Admin\AllocationController;
use App\Http\Controllers\Api\Admin\AuditLogController;
use App\Http\Controllers\Api\Admin\DashboardController;
use App\Http\Controllers\Api\Admin\DatabaseController as AdminDatabaseController;
use App\Http\Controllers\Api\Admin\GameTemplateController;
use App\Http\Controllers\Api\Admin\ImageController;
use App\Http\Controllers\Api\Admin\ImageServerController;
use App\Http\Controllers\Api\Admin\JobController;
use App\Http\Controllers\Api\Admin\NodeController;
use App\Http\Controllers\Api\Admin\ServerController as AdminServerController;
use App\Http\Controllers\Api\Admin\SettingController;
use App\Http\Controllers\Api\Admin\UserController;
use App\Http\Controllers\Api\Auth\AuthController;
use App\Http\Controllers\Api\Client\BackupController;
use App\Http\Controllers\Api\Client\ConsoleController;
use App\Http\Controllers\Api\Client\DatabaseController;
use App\Http\Controllers\Api\Client\FileController;
use App\Http\Controllers\Api\Client\FtpAccountController;
use App\Http\Controllers\Api\Client\JobController as ClientJobController;
use App\Http\Controllers\Api\Client\ServerController as ClientServerController;
use App\Http\Controllers\Api\Install\DeployController;
use App\Http\Controllers\Api\Node\AgentController;
use App\Http\Controllers\Api\Reseller\ResellerServerController;
use App\Http\Controllers\Api\Reseller\ResellerUserController;
use Illuminate\Support\Facades\Route;

Route::get('/health', fn () => response()->json([
    'status' => 'ok',
    'service' => 'gamepanel-api',
    'time' => now()->toIso8601String(),
]));

Route::prefix('install')->middleware('throttle:30,1')->group(function () {
    Route::post('/node/claim', [DeployController::class, 'claimNode']);
    Route::post('/image-server/claim', [DeployController::class, 'claimImageServer']);
    Route::post('/image-server/complete', [DeployController::class, 'completeImageServer']);
});

Route::prefix('auth')->group(function () {
    Route::post('/login', [AuthController::class, 'login']);
    Route::post('/two-factor-challenge', [AuthController::class, 'twoFactorChallenge']);
    Route::middleware('auth:sanctum')->group(function () {
        Route::get('/me', [AuthController::class, 'me']);
        Route::post('/logout', [AuthController::class, 'logout']);
        Route::post('/two-factor/enable', [AuthController::class, 'enableTwoFactor']);
        Route::post('/two-factor/confirm', [AuthController::class, 'confirmTwoFactor']);
        Route::post('/two-factor/disable', [AuthController::class, 'disableTwoFactor']);
    });
});

Route::prefix('admin')->middleware(['auth:sanctum', 'admin'])->group(function () {
    Route::get('/dashboard', DashboardController::class);

    Route::apiResource('nodes', NodeController::class);
    Route::post('/nodes/{node}/tokens', [NodeController::class, 'createToken']);
    Route::post('/nodes/{node}/deploy-token', [NodeController::class, 'createDeployToken']);

    Route::apiResource('image-servers', ImageServerController::class);
    Route::post('/image-servers/{image_server}/test', [ImageServerController::class, 'test']);
    Route::post('/image-servers/{image_server}/deploy-token', [ImageServerController::class, 'createDeployToken']);

    Route::apiResource('images', ImageController::class)->except(['update']);
    Route::post('/images/register', [ImageController::class, 'register']);
    Route::post('/images/{image}/versions', [ImageController::class, 'storeVersion']);

    Route::apiResource('templates', GameTemplateController::class);

    Route::apiResource('servers', AdminServerController::class);
    Route::post('/servers/{server}/{action}', [AdminServerController::class, 'power'])
        ->whereIn('action', ['start', 'stop', 'restart', 'kill', 'install', 'update', 'backup', 'uninstall', 'delete']);

    Route::apiResource('users', UserController::class);
    Route::apiResource('allocations', AllocationController::class)->only(['index', 'store', 'destroy']);

    Route::get('/databases', [AdminDatabaseController::class, 'index']);
    Route::get('/databases/node-access', [AdminDatabaseController::class, 'nodeAccess']);
    Route::get('/databases/{database}/reveal', [AdminDatabaseController::class, 'reveal']);

    Route::get('/jobs', [JobController::class, 'index']);
    Route::get('/jobs/{job}', [JobController::class, 'show']);

    Route::get('/audit-logs', [AuditLogController::class, 'index']);
    Route::get('/settings', [SettingController::class, 'index']);
    Route::put('/settings', [SettingController::class, 'update']);
});

Route::prefix('reseller')->middleware(['auth:sanctum', 'reseller'])->group(function () {
    Route::get('/users', [ResellerUserController::class, 'index']);
    Route::post('/users', [ResellerUserController::class, 'store']);
    Route::get('/servers', [ResellerServerController::class, 'index']);
    Route::post('/servers', [ResellerServerController::class, 'store']);
    Route::post('/servers/{server}/{action}', [ResellerServerController::class, 'power'])
        ->whereIn('action', ['start', 'stop', 'restart', 'kill', 'install', 'update']);
});

Route::prefix('client')->middleware(['auth:sanctum'])->group(function () {
    Route::get('/jobs/{job:uuid}', [ClientJobController::class, 'show']);

    Route::get('/servers', [ClientServerController::class, 'index']);
    Route::get('/servers/{server}', [ClientServerController::class, 'show']);
    Route::post('/servers/{server}/{action}', [ClientServerController::class, 'power'])
        ->whereIn('action', ['start', 'stop', 'restart', 'kill', 'install', 'update']);

    Route::get('/servers/{server}/files', [FileController::class, 'index']);
    Route::get('/servers/{server}/files/content', [FileController::class, 'content']);
    Route::post('/servers/{server}/files/write', [FileController::class, 'write']);

    Route::post('/servers/{server}/console/command', [ConsoleController::class, 'command']);
    Route::get('/servers/{server}/console/history', [ConsoleController::class, 'history']);

    Route::get('/servers/{server}/backups', [BackupController::class, 'index']);
    Route::post('/servers/{server}/backups', [BackupController::class, 'store']);
    Route::post('/servers/{server}/backups/{backup}/restore', [BackupController::class, 'restore']);
    Route::delete('/servers/{server}/backups/{backup}', [BackupController::class, 'destroy']);

    Route::get('/servers/{server}/databases', [DatabaseController::class, 'index']);
    Route::post('/servers/{server}/databases', [DatabaseController::class, 'store']);
    Route::get('/servers/{server}/databases/{database}/reveal', [DatabaseController::class, 'reveal']);
    Route::delete('/servers/{server}/databases/{database}', [DatabaseController::class, 'destroy']);

    Route::get('/servers/{server}/ftp-accounts', [FtpAccountController::class, 'index']);
    Route::post('/servers/{server}/ftp-accounts', [FtpAccountController::class, 'store']);
    Route::delete('/servers/{server}/ftp-accounts/{ftpAccount}', [FtpAccountController::class, 'destroy']);
});

Route::prefix('node')->group(function () {
    Route::post('/register', [AgentController::class, 'register']);

    Route::middleware('node.auth')->group(function () {
        Route::post('/heartbeat', [AgentController::class, 'heartbeat']);
        Route::get('/jobs', [AgentController::class, 'jobs']);
        Route::post('/jobs/{uuid}/status', [AgentController::class, 'jobStatus']);
        Route::post('/metrics', [AgentController::class, 'metrics']);
        Route::post('/events', [AgentController::class, 'events']);
        Route::get('/image-server', [AgentController::class, 'imageServerConfig']);
    });
});
