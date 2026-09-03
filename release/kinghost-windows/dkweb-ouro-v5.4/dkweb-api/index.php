<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, max-age=0');
header('Pragma: no-cache');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
header('Referrer-Policy: no-referrer');

function respond(int $status, array $payload): void
{
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function config_value(array $config, string $key): string
{
    $value = isset($config[$key]) ? trim((string) $config[$key]) : '';
    if ($value === '' || strpos($value, 'PREENCHER_') === 0) {
        respond(503, array('ok' => false, 'error' => 'bridge_not_configured'));
    }
    return $value;
}

function query_rows(mysqli $db, string $sql, string $types = '', array $params = array()): array
{
    $stmt = $db->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException('query_prepare_failed');
    }
    if ($types !== '') {
        $refs = array($types);
        foreach ($params as $index => $value) {
            $refs[] = &$params[$index];
        }
        call_user_func_array(array($stmt, 'bind_param'), $refs);
    }
    if (!$stmt->execute()) {
        $stmt->close();
        throw new RuntimeException('query_execute_failed');
    }
    $metadata = $stmt->result_metadata();
    if (!$metadata) {
        $stmt->close();
        throw new RuntimeException('query_metadata_failed');
    }
    $fields = $metadata->fetch_fields();
    $row = array();
    $bind = array();
    foreach ($fields as $field) {
        $row[$field->name] = null;
        $bind[] = &$row[$field->name];
    }
    call_user_func_array(array($stmt, 'bind_result'), $bind);
    $rows = array();
    while ($stmt->fetch()) {
        $record = array();
        foreach ($row as $name => $value) {
            $record[$name] = $value;
        }
        $rows[] = $record;
    }
    $metadata->free();
    $stmt->close();
    return $rows;
}

function normalize_document(string $value): string
{
    return preg_replace('/\D+/', '', $value) ?: '';
}

function resolve_student(mysqli $db, array $identity): array
{
    $subject = isset($identity['subject']) ? trim((string) $identity['subject']) : '';
    if ($subject === '' || strlen($subject) > 255) {
        respond(401, array('ok' => false, 'error' => 'ouro_identity_invalid'));
    }
    $cpf = normalize_document(isset($identity['cpf']) ? (string) $identity['cpf'] : '');
    if (strlen($cpf) !== 11) {
        respond(404, array('ok' => false, 'error' => 'identity_not_linked'));
    }
    $matches = query_rows(
        $db,
        "SELECT id_aluno, codigo_escola, matricula, nome
         FROM alunos
         WHERE REPLACE(REPLACE(REPLACE(REPLACE(cpf, '.', ''), '-', ''), '/', ''), ' ', '') = ?
         ORDER BY CASE WHEN situacao = 'A' THEN 0 ELSE 1 END, id_aluno DESC
         LIMIT 2",
        's',
        array($cpf)
    );
    if (count($matches) === 0) {
        respond(404, array('ok' => false, 'error' => 'dkweb_student_not_found'));
    }
    if (count($matches) > 1) {
        respond(409, array('ok' => false, 'error' => 'ambiguous_identity'));
    }
    $student = $matches[0];
    $student['match_method'] = 'cpf_verified';
    return $student;
}

function student_summary(mysqli $db, array $student): array
{
    $idAluno = (int) $student['id_aluno'];
    $school = (string) $student['codigo_escola'];

    $courses = query_rows(
        $db,
        "SELECT ac.id_aluno_curso, ac.situacao, ac.data_matricula, ac.data_inicial,
                ac.previsao_termino, ac.data_termino, ac.certificado, ac.certificado_entregue,
                COALESCE(p.nome, CONCAT('Curso ', ac.id_pacote)) AS curso
         FROM alunos_cursos ac
         LEFT JOIN pacotes p ON p.id_pacote = ac.id_pacote AND p.codigo_escola = ac.codigo_escola
         WHERE ac.id_aluno = ? AND ac.codigo_escola = ?
         ORDER BY ac.data_matricula DESC, ac.id_aluno_curso DESC
         LIMIT 100",
        'is',
        array($idAluno, $school)
    );

    $modules = query_rows(
        $db,
        "SELECT am.id_aluno_curso, am.id_aluno_modulo, am.situacao, am.data_inicial,
                am.data_final, am.termino_final, am.sequencia,
                COALESCE(m.descricao, CONCAT('Módulo ', am.id_modulo)) AS modulo,
                COALESCE(m.carga_horaria, 0) AS carga_horaria
         FROM aluno_modulos am
         INNER JOIN alunos_cursos ac ON ac.id_aluno_curso = am.id_aluno_curso
                                    AND ac.codigo_escola = am.codigo_escola
         LEFT JOIN modulos m ON m.id_modulo = am.id_modulo AND m.codigo_escola = am.codigo_escola
         WHERE ac.id_aluno = ? AND ac.codigo_escola = ?
         ORDER BY am.id_aluno_curso DESC, am.sequencia ASC
         LIMIT 500",
        'is',
        array($idAluno, $school)
    );

    $grades = query_rows(
        $db,
        "SELECT pa.id_aluno_curso, pa.nota, pa.data,
                COALESCE(pr.nome, 'Avaliação') AS avaliacao,
                COALESCE(m.descricao, CONCAT('Módulo ', pa.id_modulo)) AS modulo
         FROM provas_alunos pa
         LEFT JOIN provas pr ON pr.id_prova = pa.id_prova AND pr.codigo_escola = pa.codigo_escola
         LEFT JOIN modulos m ON m.id_modulo = pa.id_modulo AND m.codigo_escola = pa.codigo_escola
         WHERE pa.id_aluno = ? AND pa.codigo_escola = ?
         ORDER BY pa.data DESC, pa.id_prova_aluno DESC
         LIMIT 300",
        'is',
        array($idAluno, $school)
    );

    $attendance = query_rows(
        $db,
        "SELECT id_aluno_curso,
                COUNT(*) AS aulas_registradas,
                SUM(CASE WHEN presenca = 'S' THEN 1 ELSE 0 END) AS presencas,
                SUM(CASE WHEN presenca <> 'S' OR presenca IS NULL THEN 1 ELSE 0 END) AS faltas,
                MAX(data) AS ultima_aula
         FROM presenca
         WHERE id_aluno = ? AND codigo_escola = ?
         GROUP BY id_aluno_curso
         ORDER BY ultima_aula DESC
         LIMIT 100",
        'is',
        array($idAluno, $school)
    );

    $finance = query_rows(
        $db,
        "SELECT numero_lancamento, id_aluno_curso, vencimento, data_pagamento,
                quitado, estornado, valor, valor_pago, historico
         FROM caixa
         WHERE id_aluno = ? AND codigo_escola = ?
           AND (estornado IS NULL OR estornado <> 'S')
         ORDER BY vencimento DESC, numero_lancamento DESC
         LIMIT 180",
        'is',
        array($idAluno, $school)
    );

    return array(
        'ok' => true,
        'source' => 'dkweb',
        'student' => array(
            'matricula' => (string) $student['matricula'],
            'nome' => (string) $student['nome'],
            'codigo_escola' => $school,
        ),
        'courses' => $courses,
        'modules' => $modules,
        'grades' => $grades,
        'attendance' => $attendance,
        'finance' => $finance,
        'linked_by' => (string) $student['match_method'],
        'generated_at' => gmdate('c'),
    );
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond(405, array('ok' => false, 'error' => 'method_not_allowed'));
}

$configPath = dirname(__DIR__) . DIRECTORY_SEPARATOR . 'App_Data' . DIRECTORY_SEPARATOR . 'dkweb-config.php';
if (!is_file($configPath)) {
    respond(503, array('ok' => false, 'error' => 'bridge_not_configured'));
}
$config = require $configPath;
if (!is_array($config)) {
    respond(503, array('ok' => false, 'error' => 'bridge_not_configured'));
}

$raw = file_get_contents('php://input');
if (!is_string($raw) || $raw === '' || strlen($raw) > 32768) {
    respond(400, array('ok' => false, 'error' => 'invalid_payload'));
}
$timestamp = isset($_SERVER['HTTP_X_LC_TIMESTAMP']) ? (string) $_SERVER['HTTP_X_LC_TIMESTAMP'] : '';
$signature = isset($_SERVER['HTTP_X_LC_SIGNATURE']) ? strtolower((string) $_SERVER['HTTP_X_LC_SIGNATURE']) : '';
$secret = config_value($config, 'bridge_secret');
$ttl = isset($config['request_ttl_seconds']) ? max(30, min(300, (int) $config['request_ttl_seconds'])) : 120;
if (!ctype_digit($timestamp) || abs(time() - (int) $timestamp) > $ttl) {
    respond(401, array('ok' => false, 'error' => 'request_expired'));
}
$expected = hash_hmac('sha256', $timestamp . '.' . $raw, $secret);
if (!preg_match('/^[a-f0-9]{64}$/', $signature) || !hash_equals($expected, $signature)) {
    respond(401, array('ok' => false, 'error' => 'invalid_signature'));
}

$body = json_decode($raw, true);
if (!is_array($body) || ($body['action'] ?? '') !== 'summary' || !isset($body['identity']) || !is_array($body['identity'])) {
    respond(400, array('ok' => false, 'error' => 'invalid_payload'));
}

mysqli_report(MYSQLI_REPORT_OFF);
$db = @new mysqli(
    config_value($config, 'db_host'),
    config_value($config, 'db_user'),
    config_value($config, 'db_password'),
    config_value($config, 'db_name')
);
if ($db->connect_errno) {
    error_log('DKWeb bridge: database connection failed');
    respond(503, array('ok' => false, 'error' => 'dkweb_database_unavailable'));
}
$db->set_charset('utf8');

try {
    $student = resolve_student($db, $body['identity']);
    $result = student_summary($db, $student);
    $db->close();
    respond(200, $result);
} catch (Throwable $error) {
    error_log('DKWeb bridge: internal query failure');
    $db->close();
    respond(500, array('ok' => false, 'error' => 'dkweb_query_failed'));
}
