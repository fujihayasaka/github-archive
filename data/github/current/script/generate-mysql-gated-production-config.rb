#!/usr/bin/env safe-ruby
# frozen_string_literal: true

# Generate mysql-gated proxy config and a patched database.yml for the
# production deploy environment that runs the proxy.
#
# Reads config/protected/database.yml, evaluates the ERB to discover all
# database connections and their resolved host:port backends, then produces:
#
#   1. config.json   — mysql-gated proxy config with one listener per connection
#   2. database.yml  — patched copy of the original with host/port lines
#                       replaced to route the allowlisted connections through
#                       the local proxy (Unix sockets)
#
# Intended to run as a Kubernetes init container at pod boot time, writing both
# files into a shared emptyDir. The mysql-gated sidecar reads config.json; the
# unicorn container mounts the patched database.yml over the baked-in original
# via a read-only subPath volumeMount, so Rails picks it up at boot.
#
# Usage:
#   ruby script/generate-mysql-gated-production-config.rb [output-dir]
#
# Output defaults to /build/tmp/mysql-gated/

require "date"
require "erb"
require "etc"
require "fileutils"
require "json"
require "yaml"

output_dir = ARGV[0] || "/build/tmp/mysql-gated"

RAILS_ROOT = ENV.fetch("RAILS_ROOT") { File.expand_path("..", __dir__) }
DB_CONFIG_PATH = File.join(RAILS_ROOT, "config", "protected", "database.yml")

# --- Minimal stubs so the ERB in database.yml can evaluate ---
# LenientEnv wraps ENV to return nil for missing keys instead of raising
# KeyError. In the real pod all vars come from vault-secrets; this lets the
# script work gracefully in partial environments (local testing, etc.)
class LenientEnv
  def [](key)
    ENV[key]
  end

  def []=(key, val)
    ENV[key] = val
  end

  def fetch(key, default = :__unset__)
    val = ENV[key]
    return val if val
    return default unless default == :__unset__
    nil
  end

  # database.yml calls GitHub.environment["..."].to_i and .inspect on
  # the return value. When a key is missing we return nil, so these
  # must be safe: nil.to_i => 0, nil.inspect => "nil".  Ruby handles
  # both natively, but we document the expectation here.

  def to_i
    0
  end

  def include?(key)
    ENV.include?(key)
  end

  def any?(&block)
    false
  end
end

LENIENT_ENV = LenientEnv.new

module GitHub
  def self.environment
    LENIENT_ENV
  end

  def self.enterprise?
    %w[1 true].include?(ENV["ENTERPRISE"]) ||
      %w[1 true].include?(ENV["E"]) ||
      %w[1 true].include?(ENV["FI"])
  end

  def self.multi_tenant_enterprise?
    return false if enterprise?
    %w[1 true].include?(ENV["MULTI_TENANT_ENTERPRISE"])
  end

  def self.role
    ENV.fetch("GITHUB_CONFIG_ROLE", "web")
  end
end

class Integer
  def megabytes
    self * 1_048_576
  end unless method_defined?(:megabytes)
end

# The shared emptyDir is mounted into containers running as different users
# today (`git` in the github image and `github` in the mysql-gated image).
# config.json and the socket files therefore need cross-user access until we
# either split the volume or introduce a shared fsGroup. database.yml is only
# consumed by the github image, so we can tighten it further.
CONFIG_FILE_MODE = 0o644
DATABASE_FILE_MODE = 0o600
# The sticky bit prevents other users in the pod from deleting or replacing
# socket entries they do not own while still allowing the sidecar to create
# sockets in a directory initialized by another user.
SOCKET_DIR_MODE = 0o1777
# Unicorn and mysql-gated currently run as different users and do not share an
# fsGroup, so socket files must remain accessible across users.
LISTEN_SOCKET_MODE = "0666"
TLS_SSL_MODES = %w[REQUIRED VERIFY_CA VERIFY_IDENTITY].freeze

# --- Helpers ---
def tls_enabled_for_backend?(ssl_mode)
  TLS_SSL_MODES.include?(ssl_mode.to_s.upcase)
end

def write_file_with_mode(path, content, mode)
  # Remove any pre-existing file before writing. The emptyDir persists across
  # init-container restarts within the same pod, so a file left over from a
  # previous image (potentially owned by a different UID) would make
  # File.open(... TRUNC) and chmod raise EPERM.
  begin
    File.unlink(path)
  rescue Errno::ENOENT
    # Nothing to clean up.
  rescue Errno::EPERM, Errno::EACCES => e
    $stderr.puts "WARNING: could not remove stale #{path}: #{e.message}"
  end

  File.open(path, File::WRONLY | File::CREAT | File::TRUNC, mode) do |file|
    file.write(content)
  end
  File.chmod(mode, path)
end

# Ensure a directory exists and has the desired mode. Skips chmod when the
# mode already matches — the emptyDir mount point pre-exists with a
# kubelet-chosen owner (typically root) and chmod on it would fail with
# EPERM when we run as a non-root user, even though the mode is correct.
def ensure_dir_mode(path, mode)
  FileUtils.mkdir_p(path)
  current_mode = File.stat(path).mode & 0o7777
  return if current_mode == mode

  begin
    File.chmod(mode, path)
  rescue Errno::EPERM => e
    $stderr.puts "WARNING: could not chmod #{path} to 0#{mode.to_s(8)} " \
                 "(current 0#{current_mode.to_s(8)}): #{e.message}"
  end
end

# --- Render ERB and parse YAML to discover connections ---
raw_template = File.read(DB_CONFIG_PATH)

begin
  rendered = ERB.new(raw_template).result(binding)
rescue NameError, NoMethodError => e
  $stderr.puts "ERROR: ERB evaluation failed in #{DB_CONFIG_PATH}"
  $stderr.puts "  #{e.class}: #{e.message}"
  exit 1
end

begin
  config = YAML.safe_load(rendered, aliases: true, permitted_classes: [Date, Time])
rescue Psych::SyntaxError, Psych::DisallowedClass => e
  $stderr.puts "ERROR: YAML parse failed after ERB evaluation"
  $stderr.puts "  #{e.message}"
  exit 1
end

production = config["production"]
unless production
  $stderr.puts "ERROR: no 'production' section in #{DB_CONFIG_PATH}"
  exit 1
end

# --- Connection allowlist ---
# Only proxy connections in this list. All others connect directly to MySQL.
# This lets us roll out the proxy incrementally, one connection at a time.
# Set to nil or empty to proxy ALL connections.
#
# MYSQL_GATED_PROXY_ALLOWLIST overrides this default at runtime with a
# comma/space/newline-separated list of connection names. This is how
# per-environment rollouts narrow the proxy to a single connection (e.g. LUC
# proxies only artifact_registry_readonly) without forking the script.
DEFAULT_PROXY_ALLOWLIST = %w[
  mysql1_readonly
  mysql1_readonly_slow
  repositories_readonly
  repositories_readonly_slow
  repositories_actions_checks_readonly
  repositories_pushes_sharded_readonly
  issues_pull_requests_readonly
  issues_pull_requests_by_repo_owner_shard_one_readonly
  issues_pull_requests_readonly_slow
  issues_pull_requests_by_repo_owner_shard_one_readonly_slow
  notifications_readonly
  notifications_entries_readonly
  notifications_summaries_readonly
  notify_readonly
  kv_readonly
  security_overview_analytics_readonly
  spokes_readonly
  spokes_readonly_slow
  collab_readonly
  billing_readonly
  ballast_readonly
  signup_flow_readonly
  github_models_readonly
  copilot_readonly
  iam_readonly
  abilities_readonly
  authnd_readonly
  configurations_readonly
  lodge_readonly
  stratocaster_readonly
  memex_readonly
  token_scanning_service_readonly
  permissions_readonly
  migrations_readonly
  security_products_enablement_readonly
  assets_readonly
  actions_environments_readonly
  pages_readonly
  profiles_readonly
  in_product_targeting_readonly
  artifact_registry_readonly
  accounts_readonly
].freeze

# Allow per-environment overrides of the allowlist. Accepts a comma, space, or
# newline-separated list of connection names. When set (and non-empty), it
# fully replaces DEFAULT_PROXY_ALLOWLIST so an environment can proxy a single
# connection (e.g. LUC: artifact_registry_readonly) without code changes.
allowlist_override = ENV.fetch("MYSQL_GATED_PROXY_ALLOWLIST", "").split(/[\s,]+/).reject(&:empty?)
PROXY_ALLOWLIST = (allowlist_override.empty? ? DEFAULT_PROXY_ALLOWLIST : allowlist_override).freeze
$stderr.puts "Proxy allowlist (#{PROXY_ALLOWLIST.size}): #{PROXY_ALLOWLIST.join(", ")}"

# --- Determine worker count ---
# Pitchfork forks N workers per pod; all share one mysql-gated proxy.
# PoolMaxOpen must accommodate all workers × pool_size.
# GH_UNICORN_WORKER_COUNT is the canonical source: in production the overlay
# mirrors it from the unicorn container via a kustomize `replacements:` rule.
# When the var is set we require a positive integer and abort otherwise, so a
# missing/garbled replacement (e.g. the literal PLACEHOLDER_REPLACED_BY_KUSTOMIZE
# leaking through) fails the init container loudly instead of silently sizing
# the pool for 2 workers. Only when the var is absent do we fall back to
# 2 * nprocessors.
raw_worker_count = ENV["GH_UNICORN_WORKER_COUNT"]
if raw_worker_count.nil?
  worker_count = 2 * Etc.nprocessors
elsif raw_worker_count.match?(/\A\d+\z/) && raw_worker_count.to_i.positive?
  worker_count = raw_worker_count.to_i
else
  abort "FATAL: GH_UNICORN_WORKER_COUNT=#{raw_worker_count.inspect} is not a positive integer; " \
    "expected the kustomize replacement to populate it with the unicorn worker count."
end
worker_count = [worker_count, 2].max # floor at 2
$stderr.puts "Worker count: #{worker_count}"

# --- PoolMultiplex configuration ---
# Defaults to false (pinning): each frontend pins its own backend, matching the
# no-proxy connection topology. The rollout starts pinned to de-risk the proxy
# before enabling multiplexing; flip MYSQL_GATED_POOL_MULTIPLEX=true to turn it
# on (the pool idle defaults below adjust to multiplexing automatically).
pool_multiplex = ENV.fetch("MYSQL_GATED_POOL_MULTIPLEX", "false") == "true"
$stderr.puts "PoolMultiplex: #{pool_multiplex}"

# --- PoolMaxOpen override (backend connection ceiling) ---
# PoolMaxOpen caps how many backend (proxy -> MySQL) connections a listener may
# open. It is a CEILING, not a target: the pool opens connections on demand up
# to this bound and reaps idle ones via PoolIdleTimeout, so a higher ceiling
# does not force more connections to stay open.
#
# The default (computed per-connection below) is the worst-case concurrent
# backend demand = worker_count * pool_size in BOTH modes. A pitchfork worker
# handles one request at a time, but AR's load_async
# (async_query_executor = :multi_thread_pool, config/application.rb) runs queries
# on a background thread pool, so a single worker can have up to pool_size
# concurrent in-flight queries, each holding its own connection. Multiplexing's
# win is realized at runtime (backends returned between queries + idle reaping
# shrink the steady-state set to real concurrency), NOT by a lower hard ceiling
# that would only risk checkout blocking under async fan-out. Set
# MYSQL_GATED_POOL_MAX_OPEN to tune the ceiling once LUC data shows real peak
# concurrency.
pool_max_open_override = ENV.fetch("MYSQL_GATED_POOL_MAX_OPEN", "")
pool_max_open_override = pool_max_open_override.empty? ? nil : pool_max_open_override.to_i

# --- Per-connection pool-size cap ---
# Pool sizing below is driven by each connection's Rails pool size. For readonly
# connections that resolves to ACTIVE_RECORD_READONLY_POOL. Production does NOT
# set that env var, so the app's real readonly pool is the database.yml default
# of 5: the app can open up to worker_count * 5 connections to this database.
#
# For the initial canary we DELIBERATELY cap the per-connection pool size used
# for sizing at 2, so the proxy is sized for worker_count * 2 frontend/backend
# connections instead of the full worker_count * 5. This is a conservative
# starting point that keeps the proxy's blast radius small while LUC carries
# little/no traffic; it is NOT a claim that the app's pool is 2. Because the cap
# is below the real pool, under heavy load_async fan-out the app could try to
# open more frontend connections than ListenMaxConnections allows (pinning mode
# ties ListenMaxConnections to PoolMaxOpen) and the excess would be refused —
# acceptable while LUC has ~no traffic.
#
# Do NOT simply raise this cap to 5 in pinning mode: there every open frontend
# pins a dedicated backend for its whole lifetime (including the app's
# long-lived, mostly-idle pooled connections, which PoolMaxIdle:1 can't reap
# while they stay pinned), so a cap of 5 would hold up to worker_count * 5
# backends per pod with no multiplexing benefit — the backend pressure the proxy
# exists to remove. The path to the app's full pool depth is multiplexing
# (PoolMultiplex:true, which decouples backend count from frontend count), not a
# higher pinning cap. The cap is a per-connection upper bound, so lower pools
# (e.g. primaries at 1) are unaffected.
max_pool_size = [ENV.fetch("MYSQL_GATED_MAX_POOL_SIZE", "2").to_i, 1].max
$stderr.puts "MaxPoolSize (per-connection cap): #{max_pool_size}"

# --- Pool idle configuration ---
# PoolMaxIdle caps how many idle-but-open backend connections each listener
# keeps. The sensible default depends on the connection-management mode:
#
#   - Pinning (PoolMultiplex:false): each frontend pins its own backend, so the
#     backend count tracks sessions and every idle connection is pure overhead.
#     Per mysql-gated#129, default MaxIdle to the floor (1) so the proxied
#     backend count stays at or below the no-proxy baseline. (1 is the effective
#     floor; 0 means "unlimited idle" to smartconnpool.) PoolIdleTimeout is long
#     (15 min): MaxIdle already bounds the count, and smartconnpool *refreshes*
#     idle connections every IdleTimeout (close + reopen), so a short timeout
#     only churns the warm backend with no count benefit. The readonly servers'
#     wait_timeout is 1800s, and the idle worker can let a connection sit idle up
#     to ~1.1x IdleTimeout before refreshing, so the timeout must stay
#     comfortably under 1800s or a request can land on a server-killed
#     connection (the proxy doesn't validate on checkout). 900s refreshes by
#     ~990s worst case, ~810s of margin. See mysql-gated#129.
#
#   - Multiplexing (PoolMultiplex:true): backends are returned between queries,
#     so the open set floats with real concurrency and idle ones are reaped by
#     PoolIdleTimeout. Keep a warm pool: default MaxIdle to PoolMaxOpen, i.e.
#     non-binding by count, reaped only by PoolIdleTimeout.
#
# MYSQL_GATED_POOL_MAX_IDLE / MYSQL_GATED_POOL_IDLE_TIMEOUT override per env.
PINNING_DEFAULT_MAX_IDLE = 1
PINNING_DEFAULT_IDLE_TIMEOUT = "900s"
MULTIPLEX_DEFAULT_IDLE_TIMEOUT = "25s"
pool_max_idle_override = ENV.fetch("MYSQL_GATED_POOL_MAX_IDLE", "")
pool_max_idle_override = pool_max_idle_override.empty? ? nil : pool_max_idle_override.to_i
default_idle_timeout = pool_multiplex ? MULTIPLEX_DEFAULT_IDLE_TIMEOUT : PINNING_DEFAULT_IDLE_TIMEOUT
pool_idle_timeout = ENV.fetch("MYSQL_GATED_POOL_IDLE_TIMEOUT", default_idle_timeout)
$stderr.puts "PoolMaxIdle: #{pool_max_idle_override || (pool_multiplex ? "max_open" : PINNING_DEFAULT_MAX_IDLE)}"
$stderr.puts "PoolIdleTimeout: #{pool_idle_timeout}"

# --- Connection timeout configuration ---
# These govern the proxy's I/O and pool behaviour. Defaults are tuned to match
# the application's own posture for the proxied (readonly) connections so the
# proxy never becomes the limiting factor in normal operation, and to fail fast
# when something is wrong. Each is env-overridable for in-cluster tuning during
# the rollout without a code + kustomize roundtrip.
#
#   - Listen{Read,Write}Timeout (app <-> proxy, Unix socket): deliberately long
#     (≈unbounded). The application's own read_timeout (~16s) / write_timeout
#     (~1s) plus pt-kill / MAX_EXECUTION_TIME remain the authority on query
#     duration; the transparent proxy must not sever a connection the app still
#     considers healthy.
#   - Backend{Read,Write}Timeout (proxy <-> MySQL): a safety ceiling sized near
#     the app's posture (read a little above the app's 16s read_timeout; write
#     a small multiple of its 1s write_timeout) so a hung backend is reaped on
#     roughly the same timescale the app gives up, not held for minutes.
#   - BackendConnectTimeout (proxy -> MySQL dial): a healthy replica accepts a
#     connection in well under a second, so cap the dial at a couple of seconds
#     — long enough to absorb a brief blip, short enough to shed load fast when
#     a replica is degraded (the request's ~10s budget is better spent failing
#     over than waiting on a dial).
#   - PoolCheckoutTimeout: how long a request blocks to acquire a backend (incl.
#     opening one if the pool is below its ceiling) before giving up. The whole
#     request budget is ~10s (pt-kill ~10s, request timeout ~10s), so acquiring
#     a connection must be a small slice of that, leaving the bulk for the query
#     itself. In pinning mode PoolMaxOpen == app_max_conns, so the pool is sized
#     1:1 with peak demand and should never wait on contention; this mainly
#     bounds cold-start dials and the future multiplex path. Kept >= the connect
#     timeout so a legitimate cold-start checkout that has to dial a fresh
#     backend is not killed mid-handshake.
#   - PoolMaxLifetime: recycle backends a little under 5 minutes so connections
#     rebalance across read replicas as topology changes, instead of pinning to
#     one replica indefinitely.
listen_read_timeout     = ENV.fetch("MYSQL_GATED_LISTEN_READ_TIMEOUT", "3600s")
listen_write_timeout    = ENV.fetch("MYSQL_GATED_LISTEN_WRITE_TIMEOUT", "3600s")
backend_connect_timeout = ENV.fetch("MYSQL_GATED_BACKEND_CONNECT_TIMEOUT", "2s")
backend_read_timeout    = ENV.fetch("MYSQL_GATED_BACKEND_READ_TIMEOUT", "20s")
backend_write_timeout   = ENV.fetch("MYSQL_GATED_BACKEND_WRITE_TIMEOUT", "5s")
pool_checkout_timeout   = ENV.fetch("MYSQL_GATED_POOL_CHECKOUT_TIMEOUT", "3s")
pool_max_lifetime       = ENV.fetch("MYSQL_GATED_POOL_MAX_LIFETIME", "285s")
$stderr.puts "BackendConnectTimeout: #{backend_connect_timeout}"
$stderr.puts "Backend{Read,Write}Timeout: #{backend_read_timeout}/#{backend_write_timeout}"
$stderr.puts "PoolCheckoutTimeout: #{pool_checkout_timeout}"
$stderr.puts "PoolMaxLifetime: #{pool_max_lifetime}"

# --- Build one listener per database connection ---
SOCKET_DIR = File.join(output_dir, "sockets")
listeners = []
# Map connection_name -> socket path for database.yml patching
socket_map = {}

production.each do |conn_name, settings|
  next unless settings.is_a?(Hash) && settings["host"]

  # Skip connections not in the allowlist (when allowlist is active)
  if PROXY_ALLOWLIST && !PROXY_ALLOWLIST.empty?
    next unless PROXY_ALLOWLIST.include?(conn_name)
  end

  backend_host = settings["host"].to_s
  backend_port = (settings["port"] || 3306).to_i
  backend_user = settings["username"].to_s
  backend_pass = settings["password"].to_s
  backend_db   = settings["database"].to_s

  # Warn when allowlisted connections have unresolved or placeholder hosts
  if backend_host.empty? || backend_host == "default" || backend_host == "nil"
    if PROXY_ALLOWLIST&.include?(conn_name)
      $stderr.puts "WARNING: allowlisted connection #{conn_name} has unresolved host: #{backend_host.inspect}"
    end
    next
  end

  backend_tls_mode = settings["ssl_mode"]
  backend_tls = tls_enabled_for_backend?(backend_tls_mode)

  # The proxy honours whatever the application's database.yml configures for
  # ssl_mode. If a connection is not TLS-enabled that is a concern for
  # github/github, not for mysql-gated — we are transparent here, not a
  # policy enforcement point. Forwarding the configured posture keeps direct
  # and proxied connections behaviourally equivalent, so the rollout changes
  # connectivity only, not query or TLS semantics.

  # Derive Cluster + ConnectionRole tags for mysql-gated metrics from the
  # connection name. mysql-gated PR #100 made these required per-listener
  # config and validates them on startup, so the proxy refuses to boot if
  # they are missing or if ConnectionRole is anything other than
  # "reading"/"writing".
  #
  # The connection-name suffix conventions in database.yml are stable, so we
  # derive the cluster and role directly from the name. These mirror the
  # cluster/role the application already reports for the same connection, so
  # proxy-side and app-side metrics line up one-to-one.
  if conn_name.end_with?("_readonly_slow")
    cluster_tag = conn_name.sub(/_readonly_slow\z/, "")
    connection_role_tag = "reading"
  elsif conn_name.end_with?("_readonly")
    cluster_tag = conn_name.sub(/_readonly\z/, "")
    connection_role_tag = "reading"
  elsif conn_name.end_with?("_writer", "_primary")
    cluster_tag = conn_name.sub(/_(?:writer|primary)\z/, "")
    connection_role_tag = "writing"
  else
    cluster_tag = conn_name
    connection_role_tag = "writing"
  end

  socket_path = "#{SOCKET_DIR}/#{conn_name}.sock"
  socket_map[conn_name] = socket_path

  # Derive pool sizing from the Rails connection pool and worker count.
  #
  # Frontend (app -> proxy) connections: each of the worker_count pitchfork
  # workers keeps its own Rails pool of pool_size connections to this database,
  # so a pod can open up to worker_count × pool_size connections to the proxy.
  # ListenMaxConnections must allow all of them REGARDLESS of mode —
  # multiplexing reduces backend connections, not the app-side connection count.
  #
  # Backend (proxy -> MySQL) connections (PoolMaxOpen) use the same worst-case
  # ceiling in BOTH modes (see the PoolMaxOpen note above): worker_count ×
  # pool_size. Pinning needs it because every open frontend pins a backend;
  # multiplexing needs the headroom because AR load_async lets one worker run up
  # to pool_size concurrent queries, each holding a backend. The multiplexing win
  # is realized at runtime (backends returned between queries + idle reaping),
  # not by a lower ceiling. MYSQL_GATED_POOL_MAX_OPEN overrides this default.
  #
  # pool_size is capped at max_pool_size (default 2) as a deliberate conservative
  # canary starting point — the app's real readonly pool is 5 (production doesn't
  # set ACTIVE_RECORD_READONLY_POOL) — see the per-connection pool-size cap note
  # above.
  resolved_pool_size = (settings["pool"] || 1).to_i
  pool_size = [resolved_pool_size, max_pool_size].min
  app_max_conns = worker_count * pool_size
  max_open = pool_max_open_override || app_max_conns

  default_max_idle = pool_multiplex ? max_open : PINNING_DEFAULT_MAX_IDLE

  listeners << {
    "Name"                   => conn_name,
    "ListenSocket"           => socket_path,
    "ListenSocketMode"       => LISTEN_SOCKET_MODE,
    "ListenMaxConnections"   => app_max_conns,
    "ListenReadTimeout"      => listen_read_timeout,
    "ListenWriteTimeout"     => listen_write_timeout,
    "BackendAddress"         => "#{backend_host}:#{backend_port}",
    "BackendUser"            => backend_user,
    "BackendPassword"        => backend_pass,
    "BackendConnectTimeout"  => backend_connect_timeout,
    "BackendReadTimeout"     => backend_read_timeout,
    "BackendWriteTimeout"    => backend_write_timeout,
    "BackendTls"             => backend_tls,
    "BackendDatabase"        => backend_db,
    "Cluster"                => cluster_tag,
    "ConnectionRole"         => connection_role_tag,
    "BackendKeepalive"       => true,
    "BackendKeepalivePeriod" => "30s",
    "PoolMaxOpen"            => max_open,
    "PoolMaxIdle"            => pool_max_idle_override || default_max_idle,
    "PoolMaxLifetime"        => pool_max_lifetime,
    "PoolIdleTimeout"        => pool_idle_timeout,
    "PoolMultiplex"          => pool_multiplex,
  }

  $stderr.puts "  #{conn_name} #{socket_path} -> #{backend_host}:#{backend_port} [#{backend_tls ? "tls" : "plain"}]"
end

$stderr.puts "Total listeners: #{listeners.size}"

# --- Assemble proxy config ---
proxy_config = {
  "Listeners"               => listeners,
  "PoolCheckoutTimeout"     => pool_checkout_timeout,
  "AdminAddress"            => ":9091",
  "TlsFrontendEnabled"      => false,
  "MetricsStatsdAddress"    => "",
  "MetricsPrefix"           => "mysql_gated",
  "MetricsFlushInterval"    => "10s",
  "LogLevel"                => "info",
  "LogFormat"               => "logfmt",
}

# --- Patch database.yml to route each connection through its proxy socket ---
# Replace host: and port: lines with socket: for proxied connections.
# Preserves all other ERB expressions (pool, timeout, credentials, etc.)
lines = raw_template.lines
output_lines = []
in_production = false
current_conn = nil

lines.each do |line|
  if line =~ /\Aproduction:\s*\z/
    in_production = true
    output_lines << line
    next
  end

  # End of production section
  if in_production && line =~ /\A[a-z]/ && line !~ /\A\s/
    in_production = false
    current_conn = nil
  end

  unless in_production
    output_lines << line
    next
  end

  # Connection section header (2-space indented)
  if line =~ /\A\s{2}([a-z]\w+):\s*\z/
    current_conn = $1
  end

  if current_conn && socket_map[current_conn]
    socket_path = socket_map[current_conn]

    # Replace host: with empty string and add backend_host:, socket:, and
    # keepalive override. We must blank host: (not just remove it) because
    # YAML merge keys (<<: *production_defaults) would bring it back from
    # the anchor. Trilogy ignores socket: when host: is set, so host must
    # be nil/empty. backend_host: preserves the real hostname for metrics,
    # Failbot, and staffbar, and is emitted as a literal string using the
    # already-resolved host from the parsed config — we must NOT re-wrap
    # the raw ERB expression in extra quotes, because every `host:` line in
    # the template renders the value via `.inspect` (already a quoted
    # string). Wrapping that in outer quotes would produce invalid YAML
    # like `backend_host: ""hostname""` after Rails re-evaluates ERB at
    # boot. keepalive_enabled must be false because SO_KEEPALIVE returns
    # ENOTSUP on Unix domain sockets, crashing Trilogy.
    if line =~ /\A(\s+)host:\s+\S/
      indent = $1
      resolved_host = production[current_conn]["host"].to_s
      output_lines << "#{indent}host:\n"
      output_lines << "#{indent}backend_host: #{resolved_host.inspect}\n"
      output_lines << "#{indent}socket: #{socket_path.inspect}\n"
      output_lines << "#{indent}keepalive_enabled: false\n"

      next
    end

    # Drop port: line (sockets don't use ports)
    if line =~ /\A(\s+)port:\s/
      next
    end

    # Drop ssl_mode (Unix sockets don't use TLS, and STARTTLS fails on them)
    if line =~ /\A(\s+)ssl_mode:\s/
      next
    end
  end

  output_lines << line
end

# --- Write output ---
# We deliberately do NOT chmod `output_dir` itself. In production it is the
# kubelet-created emptyDir mount point, owned by root and already 0755; we run
# as a non-root user and cannot alter it. The subdir + files we create below
# are the ones whose modes we actually control.
FileUtils.mkdir_p(output_dir)
ensure_dir_mode(SOCKET_DIR, SOCKET_DIR_MODE)

config_path = File.join(output_dir, "config.json")
write_file_with_mode(config_path, JSON.pretty_generate(proxy_config), CONFIG_FILE_MODE)
$stderr.puts "Wrote #{config_path} (#{listeners.size} listeners) mode=0#{CONFIG_FILE_MODE.to_s(8)}"

db_path = File.join(output_dir, "database.yml")
write_file_with_mode(db_path, output_lines.join, DATABASE_FILE_MODE)
$stderr.puts "Wrote #{db_path} (#{socket_map.size} connections patched) mode=0#{DATABASE_FILE_MODE.to_s(8)}"
$stderr.puts "Prepared #{SOCKET_DIR} mode=0#{SOCKET_DIR_MODE.to_s(8)} socket_mode=#{LISTEN_SOCKET_MODE}"
