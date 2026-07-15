<?php

return [
    'default' => env('BROADCAST_CONNECTION', 'reverb'),

    'connections' => [
        'reverb' => [
            'driver' => 'reverb',
            'key' => env('REVERB_APP_KEY', 'gamepanel-key'),
            'secret' => env('REVERB_APP_SECRET', 'gamepanel-secret'),
            'app_id' => env('REVERB_APP_ID', 'gamepanel'),
            'options' => [
                'host' => env('REVERB_HOST', 'reverb'),
                'port' => env('REVERB_PORT', 8080),
                'scheme' => env('REVERB_SCHEME', 'http'),
                'useTLS' => env('REVERB_SCHEME', 'http') === 'https',
            ],
        ],

        'log' => [
            'driver' => 'log',
        ],

        'null' => [
            'driver' => 'null',
        ],
    ],
];
