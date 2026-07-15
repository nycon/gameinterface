<?php

namespace App\Events;

use App\Models\ServerEvent;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcastNow;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class ServerOutputBroadcast implements ShouldBroadcastNow
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    public function __construct(public ServerEvent $event) {}

    public function broadcastOn(): array
    {
        return [new PrivateChannel('servers.'.$this->event->server_id)];
    }

    public function broadcastAs(): string
    {
        return 'console.output';
    }

    public function broadcastWith(): array
    {
        return [
            'id' => $this->event->id,
            'type' => $this->event->type,
            'message' => $this->event->message,
            'meta' => $this->event->meta,
            'created_at' => $this->event->created_at?->toIso8601String(),
        ];
    }
}
