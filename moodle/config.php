<?php
// Moodle config.php — reads all per-environment values from environment
// variables so the same image is portable across servers. Baked into the
// image at /var/www/html/config.php; the values come from .env via
// docker-compose.yml.

unset($CFG);
global $CFG;
$CFG = new stdClass();

// --- Database -------------------------------------------------------------
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = getenv('MOODLE_DB_HOST') ?: 'db';
$CFG->dbname    = getenv('MOODLE_DB_NAME') ?: 'moodle';
$CFG->dbuser    = getenv('MOODLE_DB_USER') ?: 'moodle';
$CFG->dbpass    = getenv('MOODLE_DB_PASSWORD') ?: '';
$CFG->prefix    = getenv('MOODLE_DB_PREFIX') ?: 'mdl_';
$CFG->dboptions = [
    'dbpersist'   => 0,
    'dbport'      => (int)(getenv('MOODLE_DB_PORT') ?: 3306),
    'dbsocket'    => '',
    'dbcollation' => 'utf8mb4_general_ci',
];

// --- URLs and paths -------------------------------------------------------
$CFG->wwwroot  = rtrim(getenv('MOODLE_WWWROOT') ?: 'https://localhost', '/');
$CFG->dataroot = getenv('MOODLE_DATAROOT') ?: '/var/www/moodledata';
$CFG->admin    = 'admin';
$CFG->directorypermissions = 02775;

// --- Reverse proxy --------------------------------------------------------
// Caddy terminates HTTPS and forwards plain HTTP to Apache. Moodle needs to
// know (a) the original scheme so links stay https, and (b) the real client
// IP so access logs / IP-based rules work.
$CFG->sslproxy = true;
if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO'])) {
    $_SERVER['HTTPS'] = ($_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') ? 'on' : 'off';
}
if (!empty($_SERVER['HTTP_X_FORWARDED_FOR'])) {
    $remote = explode(',', $_SERVER['HTTP_X_FORWARDED_FOR'])[0];
    $_SERVER['REMOTE_ADDR'] = trim($remote);
}
// Do NOT enable $CFG->reverseproxy here. Moodle's reverseproxy mode (see
// lib/setuplib.php) requires the proxy to *rewrite* the Host header to an
// internal name and throws 'reverseproxyabused' when Host matches wwwroot.
// Our Caddy preserves the original Host (the standard reverse-proxy
// behavior), so reverseproxy=true would trip that check on every request.

// --- SMTP (only configured if MOODLE_SMTP_HOSTS is set) -------------------
if (getenv('MOODLE_SMTP_HOSTS')) {
    $CFG->smtphosts    = getenv('MOODLE_SMTP_HOSTS');
    $CFG->smtpuser     = getenv('MOODLE_SMTP_USER') ?: '';
    $CFG->smtppass     = getenv('MOODLE_SMTP_PASSWORD') ?: '';
    $CFG->smtpsecure   = getenv('MOODLE_SMTP_SECURE') ?: '';
    $CFG->smtpauthtype = getenv('MOODLE_SMTP_AUTH') ?: 'LOGIN';
    $CFG->smtpmaxbulk  = (int)(getenv('MOODLE_SMTP_MAXBULK') ?: 1);
}
if (getenv('MOODLE_NOREPLY')) {
    $CFG->noreplyaddress = getenv('MOODLE_NOREPLY');
}
if (getenv('MOODLE_ADMIN_EMAIL')) {
    $CFG->supportemail = getenv('MOODLE_ADMIN_EMAIL');
}

require_once(__DIR__ . '/lib/setup.php');

// No closing PHP tag — intentional, prevents trailing-whitespace problems.
