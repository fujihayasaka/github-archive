# typed: ignore
# frozen_string_literal: true

# Pichfork config
# --------------
#
# This file configures Pitchfork before boot
#
# Doc: https://github.com/Shopify/pitchfork/blob/master/docs/CONFIGURATION.md
#
# To start the server process manually:
#
# pitchfork -c /data/github/current/config/pitchfork.rb -E production -D

require "rack/server_id"

require "socket"
hostname = Socket.gethostname.split(".").first
GitHub.component = :unicorn
is_gitauth = !!ENV["GITAUTH"]
gitauth = is_gitauth ? "-gitauth" : ""
worker_boot_delay = (ENV.fetch("GH_WORKER_BOOT_DELAY", "1") == "1")
log_destination = ENV.fetch("GH_LOG_DESTINATION", "file")

rails_env = ENV["RAILS_ENV"] || "production"
rails_root = File.expand_path(ENV["RAILS_ROOT"] || "/data/github/current")

worker_processes GitHub.unicorn_worker_count
check_client_connection true if GitHub.unicorn_check_client_connection?
early_hints true if GitHub.early_hints?

if rails_env != "development"
  # Restart any workers that haven't responded in 30 seconds. For gitauth, give
  # us 130 so it's bigger than the 120 for _commit_refs
  timeout is_gitauth ? 130 : 30

  if is_gitauth
    # Set 'gitauth' as the role unless the environment want so specify something
    # else

    GitHub.role = :gitauth
    if role = ENV["GITHUB_CONFIG_ROLE"]
      GitHub.role = role
    end

    gitauth_port = ENV["GITHUB_GITAUTH_PORT"] || 4328
    if GitHub.enterprise?
      listen gitauth_port
    else
      listen "127.0.0.1:#{gitauth_port}"
    end
  else
    # Ideally, GitHub.role would be sourced from the GITHUB_CONFIG_ROLE env var
    # rather than gleaned from the hostname like we do here. For god-managed
    # web processes, we inject that env var via the god config. Unfortunately, even
    # if we ask god to reload the config, our web processes will *never* pick up the
    # new variables on a graceful restart (because the new unicorn master is
    # forked from the old master, not god). Thus, it would be a truly obnoxious
    # undertaking to roll out env-vars completely until we're entirely containerized.
    unless ENV["GITHUB_CONFIG_ROLE"]
      GitHub.role = GitHub.role_from_host
    end

    unicorn_port = ENV["GITHUB_UNICORN_PORT"] || 4327
    if GitHub.enterprise?
      listen unicorn_port
    else
      listen "127.0.0.1:#{unicorn_port}"
      listen "#{hostname}:#{unicorn_port}"
    end
  end
  listen "#{rails_root}/tmp/sockets/unicorn#{gitauth}.sock", backlog: 2048 unless GitHub.enterprise?

  if log_destination == "file"
    # Write unicorn stdout/stderr to unicorn.log
    logfile = "#{rails_root}/log/#{is_gitauth ? 'gitauth' : 'unicorn'}.log"
    stderr_path logfile
    stdout_path logfile
  end
else # rails_env == "development"
  # feels better than unassigned
  GitHub.role = :development

  setpgid false

  if RACKUP[:port] != 8080
    puts "listening on #{RACKUP[:port]}"
  else
    if !is_gitauth
      listen "127.0.0.1:3000"
    else
      listen "127.0.0.1:4327"
    end
  end
  timeout 5 * 60

  # write stuff to console immediately
  $stderr.sync = true
  $stdout.sync = true

  # TODO: why does this cause spawning children to fail?
  #       with this uncommented run `EXPERIMENTAL_PITCHFORK=1 script/unicorn-server`
  #       see message: `Failed to spawn a worker twice in a row. Corrupted mold process?`
  # store the AR schema cache file
  # require "github/config/mysql"
  # GitHub.load_activerecord
end

warn "Pitchfork server starting in #{GitHub.runtime.current} mode ..."

GitHub.unicorn_master_pid = Process.pid
GitHub.unicorn_master_start_time = Time.now.utc

after_mold_fork do |server, _mold|
  t1 = Time.now
  server.logger.info "mold before_first_fork=start"

  # This is a workaround for https://github.com/grpc/grpc/issues/8798. GRPC
  # doesn't provide a mechanism for resetting shared resources after forking,
  # so we need to make sure no shared resources were created before forking.
  # The shared resources are created the first time a channel is created, so
  # raise if any channels exist. Once the above issue is fixed, this can be
  # replaced with a reset in after_fork.
  # This workaround also exists in config/resqued/github-environment.rb.
  # GRPC is not supposed to be used in github/github, but is still in use for
  # legacy reasons.
  # See https://github.com/github/c2c-actions-experience/issues/4982
  if defined?(GRPC)
    ObjectSpace.each_object(GRPC::Core::Channel) do |_chan|
      server.logger.error "mold before_fork=grpc_check error='a grpc channel was created before forking'"
      raise RuntimeError, "A GRPC channel was created before forking! Please " +
                          "create GRPC resources after forking."
    end
  end

  # Docker/Kubernetes send SIGTERM to shutdown processes inside a container.
  # Unicorn treats SIGTERM as a hard close and will drop connections when
  # running under Kubernetes, so override Unicorn's SIGTERM handler and send
  # ourself a SIGQUIT (graceful) instead.
  if GitHub.kube?
    Signal.trap "TERM" do
      puts "mold before_fork=term_handler action=QUIT"
      Process.kill "QUIT", Process.pid
    end
  end

  # Nomad in GHES will send SIGINT to shutdown the process inside the container.
  # Sleep for 30 seconds to allow haproxy time to shift traffic to another instance.
  # Then send ourself a SIGQUIT to perform a (graceful) shutdown.
  if GitHub.enterprise?
    Signal.trap "INT" do
      puts "mold before_fork=int_handler action=sleep"
      sleep(30)
      puts "mold before_fork=int_handler action=QUIT"
      Process.kill "QUIT", Process.pid
    end
  end

  if Process.respond_to?(:warmup)
    # Process.warmup tells Ruby that the app is booted, allowing it to optimize
    # the application
    # In Ruby 3.3 this includes (it will change in the future):
    #  - Run GC and compaction
    #  - Promote all surviving objects to oldgen
    #  - Other minor changes to improve GC and CoW
    Process.warmup
  else
    # "Nakayoshi Fork" technique
    # Ruby's object tags include two bits indicating the "age" of the object,
    # which can be unfriendly to CoW memory as they age.
    # Performing three Minor GCs ensures that all objects have fully aged and are
    # in the "old" generation (we assume any object alive at this point will
    # likely remain so for the lifetime of the server).
    3.times { GC.start(full_mark: false) }

    # Finally, perform a Major GC to free any remaining oldgen objects.
    GC.start

    # Enabling this should improve CoW and GC performance.
    if GC.respond_to?(:compact)
      GC.compact
    end
  end

  duration = (Time.now - t1) * 1000
  server.logger.info "mold after_mold_fork=end duration=#{'%.2f' % duration}"
end

# Called in the mold before forking _each_ worker process.
# In dotcom production this will be run 16 times (as of 2022-09-13)
before_fork do |server|
  t1 = Time.now
  server.logger.info "mold before_fork=start"

  # Give workers some time to boot (avoid fork-bomb during deploy).
  # Please read https://github.com/github/github/pull/38530
  # and https://github.com/github/github/pull/114145 before attempting
  # to change this sleep value.
  if worker_boot_delay && rails_env == "production" && !(GitHub.enterprise? || GitHub.kube?)
    sleep([60.0 / GitHub.unicorn_worker_count, 2].min)
  end

  # Run any pending setup work before forking off the new process. This
  # includes things like switching runtime modes between dotcom and enterprise
  # and bootstrapping the gem environment if needed.
  if rails_env == "development" && File.exist?("tmp/runtime/pending")
    system "script/setup"
  end

  # Attempt to memoize the GHE license file in the master process.
  # Prevents the license file from being read on the first request,
  # which is slow and can cause timeouts on requests to gitauth.
  # TODO: unicorn.rb is not the ideal place for preloading behaviour. Consider
  # moving this to application.rb or elsewhere.
  if GitHub.enterprise? && rails_env != "development"
    ActiveRecord::Base.connection.reconnect! # rubocop:disable GitHub/DoNotCallMethodsOnActiveRecordBase
    GitHub::Enterprise.license
    GitHub.enterprise_first_run?
  end

  unless GitHub.enterprise?
    GitHub::Connect::Authenticator.load_vaults
  end

  duration = (Time.now - t1) * 1000
  server.logger.info "mold before_fork=end duration=#{'%.2f' % duration}"
  GitHub::BootMetrics.record_state("unicorn.before_fork", duration: duration)
  GitHub::BootMetrics.send_to_datadog
end

# Called in the worker immediately after forking.
after_worker_fork do |server, worker|
  t1 = Time.now

  GitHub.dogstats.increment("unicorn.after_fork.count")

  # Start the debug dap server for the vscode extension to attach to
  if rails_env == "development" && ENV["DEBUG_DAP"] && !is_gitauth
    require "debug/open_nonstop"
  end

  server.logger.info "worker=#{worker.nr} after_fork=start"

  ##
  # Do nothing on SIGTERM from Kubernetes (see comment in before_fork)
  if GitHub.kube?
    Signal.trap "TERM" do
      puts "worker=#{worker.nr} after_fork=term_handler action=ignore"
    end
  end

  ##
  # Do nothing on SIGINT from GHES (see comment in before_fork)
  if GitHub.enterprise?
    Signal.trap "INT" do
      puts "worker=#{worker.nr} after_fork=int_handler action=ignore"
    end
  end

  Rack::ServerId.reset!

  ##
  # Unicorn master loads the app then forks off workers - because of the way
  # Unix forking works, we need to make sure we aren't using any of the parent's
  # sockets, e.g. db connection
  ActiveRecord::Base.connection_handler.clear_all_connections!(:all)

  if rails_env != "development" || ENV["PRELOAD"]
    GitHub.cache.reset
    GitHub.cache_partitions.keys.each do |k|
      next if k == :global
      GitHub.cache.for_partition(k).reset
    end
    GitHub.job_coordination_redis._client.disconnect
    GitHub.kv = nil
    FeatureFlag.cache_client&.reset
  end

  # setup backtrace dumping on USR2
  # Unicorn.trap_introspect_signal

  GitHub.unicorn_master_pid = Process.ppid
  GitHub.unicorn_worker_start_time = Time.now.utc
  GitHub.unicorn_worker_number = worker.nr
  GitHub.unicorn_worker_pid = Process.pid

  if GitHub.enterprise?
    # Flush memcache when the hostname and gravatar settings are modified.
    # We remove the script since we only want to use it once.
    # If those settings are modified again the script will be generated there.
    flush = "#{rails_root}/../shared/flush-cache.sh"
    %x{test -f #{flush} && . #{flush} && rm -f #{flush}}

    # reload yaml config
    GitHub.reload_config
  end

  GitHub::InstrumentationThread.start

  duration = (Time.now - t1) * 1000
  server.logger.info "worker=#{worker.nr} after_fork=end duration=#{'%.2f' % duration}"
end

require "pitchfork/log_preload"
require "github/process_name"

# Called by the master process right before exec()-ing the new unicorn binary.
# This is useful for freeing certain OS resources that you do NOT wish to share
# with the reexeced child process.
#
# We need to make sure the RUBYLIB load path is rebuilt with the current set of
# gems so clear out RUBYLIB.
before_fork do |server|
  t1 = Time.now
  server.logger.info "mold before_exec=start"
  ENV.delete("RUBYLIB")

  # load gpanel config if it exists
  GitHub.reload_gpanel_config

  # enterprise uses environment variables to inject customer configuration. When
  # the unicorn reloads due to a customer update, it needs to slurp up the latest
  # environment variables from the shared/env.d/*.sh files.
  if GitHub.enterprise? && ENV.key?("ENTERPRISE_APP_INSTANCE")
    lines = %x{. #{ENV["ENTERPRISE_APP_INSTANCE"]}/.app-config/production.sh && env}.split("\n")
    enterprise_variables = lines.grep(/\A(ENTERPRISE|GH_|GITHUB)/).map { |l| l.split("=", 2) }

    enterprise_variables.each do |(key, value)|
      ENV[key] = value
    end

    %w(RUBYOPT GEM_HOME GEM_PATH).each do |opt|
      ENV.delete(opt)
    end
  end
  duration = (Time.now - t1) * 1000
  server.logger.info "master before_exec=end duration=#{'%.2f' % duration}"
end

after_worker_ready do |_server, worker|
  GitHub::ProcessName.instance.update(rack_server: "pitchfork", worker_number: worker.nr)
  GitHub::ProcessName.instance.setproctitle
end

after_monitor_ready do |_server|
  # Monitor is setup after the initial set of workers are spawned
  # This is a good time to set let kube know the workers are ready for requests
  if GitHub.kube?
    File.open(GitHub.kube_workers_ready_file, "w") do |f|
      f.puts(Process.pid)
    end
  end
end

after_worker_exit do |server, _worker, status|
  # status is a Process::Status instance for the exited worker process
  unless status.success?
    GitHub.dogstats.increment("unicorn.worker.death")
    server.logger.error("worker process failure: #{status.inspect}")
  end
end
