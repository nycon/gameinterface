<?php

namespace App\Services;

use App\Models\ImageServer;

class ImageServerConnectionTester
{
    public function __construct(private readonly EncryptionService $encryption) {}

    /**
     * @return array{ok: bool, message: string, details?: array}
     */
    public function test(ImageServer $server): array
    {
        if (! in_array($server->protocol, ['sftp', 'ftps', 'ftp'], true)) {
            return ['ok' => false, 'message' => 'Unsupported protocol'];
        }

        if ($server->protocol === 'ftp') {
            $probe = $this->tcpProbe($server->hostname, (int) $server->port, 5);
            return [
                'ok' => $probe['ok'],
                'message' => $probe['ok']
                    ? 'Plain FTP reachable — use only on trusted networks'
                    : 'FTP TCP probe failed: '.$probe['error'],
                'details' => [
                    'protocol' => $server->protocol,
                    'host' => $server->hostname,
                    'port' => $server->port,
                    'warning' => 'Prefer SFTP or FTPS in production',
                    'tcp' => $probe,
                ],
            ];
        }

        $hasAuth = filled($server->password_encrypted) || filled($server->ssh_key_encrypted);
        if (! $hasAuth) {
            return ['ok' => false, 'message' => 'No credentials configured'];
        }

        $probe = $this->tcpProbe($server->hostname, (int) $server->port, 5);
        if (! $probe['ok']) {
            return [
                'ok' => false,
                'message' => 'Host/port not reachable: '.$probe['error'],
                'details' => [
                    'protocol' => $server->protocol,
                    'host' => $server->hostname,
                    'port' => $server->port,
                    'tcp' => $probe,
                ],
            ];
        }

        return [
            'ok' => true,
            'message' => 'TCP probe OK — full auth/download is verified by the node agent',
            'details' => [
                'protocol' => $server->protocol,
                'host' => $server->hostname,
                'port' => $server->port,
                'base_path' => $server->base_path,
                'username' => $server->username,
                'auth' => filled($server->ssh_key_encrypted) ? 'ssh_key' : 'password',
                'tcp' => $probe,
            ],
        ];
    }

    /**
     * @return array{ok: bool, latency_ms?: int, error?: string}
     */
    private function tcpProbe(string $host, int $port, int $timeoutSeconds): array
    {
        $start = hrtime(true);
        $errno = 0;
        $errstr = '';
        $socket = @fsockopen($host, $port, $errno, $errstr, $timeoutSeconds);
        $latency = (int) ((hrtime(true) - $start) / 1_000_000);

        if (! is_resource($socket) && ! ($socket instanceof \Socket)) {
            return ['ok' => false, 'error' => trim($errstr !== '' ? $errstr : "errno {$errno}")];
        }

        fclose($socket);

        return ['ok' => true, 'latency_ms' => $latency];
    }

    public function credentialsForAgent(ImageServer $server): array
    {
        return [
            'protocol' => $server->protocol,
            'host' => $server->hostname,
            'port' => $server->port,
            'base_path' => $server->base_path,
            'username' => $server->username,
            'password' => $this->encryption->decrypt($server->password_encrypted),
            'private_key' => $this->encryption->decrypt($server->ssh_key_encrypted),
            'public_url' => $server->public_url,
        ];
    }
}
