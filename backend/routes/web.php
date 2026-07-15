<?php

use App\Http\Controllers\Api\Install\DeployController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::middleware('throttle:60,1')->group(function () {
    Route::get('/install/node/{token}.sh', [DeployController::class, 'nodeScript'])
        ->where('token', 'gpd_[A-Za-z0-9]+');
    Route::get('/install/image-server/{token}.sh', [DeployController::class, 'imageServerScript'])
        ->where('token', 'gpd_[A-Za-z0-9]+');
});
