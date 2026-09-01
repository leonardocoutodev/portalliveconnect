<?php
declare(strict_types=1);

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store, max-age=0');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');
@set_time_limit(120);

const INSTALL_KEY = '044054b2ad93ed3238944c407e23b61b';
const RELEASE_BASE = 'https://raw.githubusercontent.com/leonardocoutodev/portalliveconnect/0140bffb6cf01e8d2e3b4573a7fb856fb7780377/release/kinghost-windows/portal-unificado-v5.5/';

$manifest = array(
    'area-do-aluno/index.htm' => '109a7fa3d688999205e5fff6678cb027b706ed821e19bda636b5a65c7e32869a',
    'area-do-aluno/index.html' => '109a7fa3d688999205e5fff6678cb027b706ed821e19bda636b5a65c7e32869a',
    'assets/css/dkweb-panel.css' => '6a6ac70e97ff8e329ba95221dee481a720d5e1fbfaff7d07e037410822ae4eae',
    'assets/js/v360/app.js' => 'd4b429961f46a16c187559abcaec1a178910a548fcf65ad013c2b48cf81142c7',
    'assets/js/v360/api.js' => '399095488251752eeac417b94224a14e614fb751ff9f376dd9746f4392c8925a',
    'assets/js/v360/config.js' => '0fb4e3ff254272d26ee4b28ee9df148dd744fda11f9dd07a69f80e49d91c8199',
    'assets/js/v360/pages.js' => 'f48976a6f05b4870f0162860ded356db1a80df8835c0d1551106af019e4be15a',
    'dkweb-api/index.php' => '881a78670d73ce2a52f32a67ff9e0692951325895c7e9d6d5f6152b414cba849',
    'dkweb-api/web.config' => '0387064a13ac98ec89ff9031cdd364aaff67fd20201375935f4f343d88653ee7',
    'App_Data/dkweb-config.example.php' => '40f8aa4c7d7e0ede1ec98105483d95c311c5e8bf2f85b2a02f2cbdb4f0e57fd9',
    'App_Data/web.config' => '8d10e9661f90d0de20a4fc95ab24632dafede113a529b9f75bb9a61cdb0ce1e4',
    'ATIVACAO_FINAL_PORTAL_UNIFICADO_V5.5.txt' => '83a7be15ac59b76922ff39efdd9ca25929bb098179b1337075b4ff9cbc7735e2',
    'DEPLOY_PORTAL_UNIFICADO_V5.5.txt' => '9356bc104bc28cd98ac79dfe0f7c10035019f578d631cc7b0f5b3697c2d75042',
    'RELEASE_NOTES_V5.5.txt' => '8755d6b6246b67d3906eadc18b4212620f516a7dd346d421285dffc5cee22545',
);

function page(string $title, string $message, bool $button = false): void
{
    $safeTitle = htmlspecialchars($title, ENT_QUOTES, 'UTF-8');
    $safeMessage = htmlspecialchars($message, ENT_QUOTES, 'UTF-8');
    $action = htmlspecialchars($_SERVER['REQUEST_URI'], ENT_QUOTES, 'UTF-8');
    $form = $button ? '<form method="post" action="' . $action . '"><button type="submit">Instalar atualização V5.5</button></form>' : '';
    echo '<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' . $safeTitle . '</title><style>body{margin:0;background:#f3f7ff;color:#102a56;font:16px system-ui,-apple-system,Segoe UI,sans-serif;display:grid;place-items:center;min-height:100vh}.box{width:min(620px,calc(100% - 40px));background:#fff;border:1px solid #dce7fa;border-radius:22px;padding:32px;box-shadow:0 18px 50px #103b7a20}h1{margin-top:0;color:#083c9b}p{line-height:1.6}button{border:0;border-radius:12px;background:#0b57d0;color:#fff;padding:14px 20px;font-size:16px;font-weight:700;cursor:pointer}</style></head><body><main class="box"><h1>' . $safeTitle . '</h1><p>' . $safeMessage . '</p>' . $form . '</main></body></html>';
    exit;
}

function remote_url(string $path): string
{
    $parts = explode('/', $path);
    return RELEASE_BASE . implode('/', array_map('rawurlencode', $parts));
}

function download_file(string $url)
{
    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 10);
        curl_setopt($ch, CURLOPT_TIMEOUT, 30);
        curl_setopt($ch, CURLOPT_USERAGENT, 'LiveConnect-Installer/5.5');
        $data = curl_exec($ch);
        $status = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if (is_string($data) && $status === 200) {
            return $data;
        }
    }
    $context = stream_context_create(array('http' => array('timeout' => 30, 'header' => "User-Agent: LiveConnect-Installer/5.5\r\n")));
    return @file_get_contents($url, false, $context);
}

$key = isset($_GET['chave']) ? (string) $_GET['chave'] : '';
if (!hash_equals(INSTALL_KEY, $key)) {
    http_response_code(404);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    page('Atualização Live Connect V5.5', 'O instalador fará backup dos arquivos atuais e publicará o Portal unificado EAD + presencial. Nenhuma senha será alterada.', true);
}

$downloads = array();
foreach ($manifest as $path => $expectedHash) {
    $data = download_file(remote_url($path));
    if (!is_string($data) || !hash_equals($expectedHash, hash('sha256', $data))) {
        page('Instalação interrompida', 'Não foi possível baixar ou validar ' . $path . '. Nenhum arquivo do site foi alterado.');
    }
    $downloads[$path] = $data;
}

$root = __DIR__;
$backupRelative = '_backup_lc55_' . gmdate('Ymd_His');
$backupRoot = $root . DIRECTORY_SEPARATOR . $backupRelative;
if (!@mkdir($backupRoot, 0755, true) && !is_dir($backupRoot)) {
    page('Instalação interrompida', 'Não foi possível criar o backup. Nenhum arquivo do site foi alterado.');
}

$changed = array();
$created = array();
try {
    foreach ($downloads as $relative => $data) {
        $localRelative = str_replace('/', DIRECTORY_SEPARATOR, $relative);
        $destination = $root . DIRECTORY_SEPARATOR . $localRelative;
        $directory = dirname($destination);
        if (!is_dir($directory) && !@mkdir($directory, 0755, true) && !is_dir($directory)) {
            throw new RuntimeException('directory_failed');
        }
        if (is_file($destination)) {
            $backupFile = $backupRoot . DIRECTORY_SEPARATOR . $localRelative;
            $backupDirectory = dirname($backupFile);
            if (!is_dir($backupDirectory) && !@mkdir($backupDirectory, 0755, true) && !is_dir($backupDirectory)) {
                throw new RuntimeException('backup_directory_failed');
            }
            if (!@copy($destination, $backupFile)) {
                throw new RuntimeException('backup_failed');
            }
        } else {
            $created[] = $destination;
        }
        if (@file_put_contents($destination, $data, LOCK_EX) === false) {
            throw new RuntimeException('write_failed');
        }
        $changed[$relative] = $destination;
    }
} catch (Throwable $error) {
    foreach ($changed as $relative => $destination) {
        $backupFile = $backupRoot . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relative);
        if (is_file($backupFile)) {
            @copy($backupFile, $destination);
        }
    }
    foreach ($created as $destination) {
        @unlink($destination);
    }
    page('Instalação revertida', 'Ocorreu uma falha ao gravar os arquivos. O instalador restaurou a versão anterior.');
}

@unlink(__FILE__);
page('Atualização instalada', 'A V5.5 foi publicada com sucesso. O backup foi preservado na pasta ' . $backupRelative . ' e este instalador foi removido automaticamente.');
b6f6c5b9f5719cc03f7cde3fad40997de964eb6213310d4beb1f44d4d66a5558  dkweb-integration/kinghost/installer-lc55.php
