# typed: false
# frozen_string_literal: true

# When unicorn kills a worker process due to exceeding the timeout, we want to
# get a backtrace of what the worker was doing. Send a kill -USR2 and wait a bit
# before killing with -KILL. The worker process traps the USR2, dumps the
# backtrace to stderr, and reports to failbot.

require "unicorn"
require "timeout"
require "failbot"
require "failbot/middleware"

# Tap into the master's kill logic
class Unicorn::HttpServer
  def kill_worker_with_introspect(signal, wpid)
    # Increment unicorn death counter
    GitHub.dogstats.increment("unicorn.worker.death")
    logger.info "master kill_worker signal=#{signal} wpid=#{wpid}"

    if signal == :KILL
      signal_worker_introspect(wpid)
    end
    kill_worker_without_introspect(signal, wpid)
  end
  alias_method :kill_worker_without_introspect, :kill_worker
  alias_method :kill_worker, :kill_worker_with_introspect

  def signal_worker_introspect(wpid)
    Process.kill(:USR2, wpid)
    sleep 0.5
  end
end

# This must be called in the config/unicorn.rb after_fork hook to setup the
# signal handling in the worker.
module Unicorn
  class WorkerTimeout < Timeout::Error
    attr_accessor :backtrace
  end

  def self.trap_introspect_signal
    trap "USR2" do
      # dump backtrace to stderr
      warn "== worker [#$$] USR2 received. dumping backtrace."
      warn caller.join("\n")
      warn "=="

      # send exception to failbot
      boom = WorkerTimeout.new("unicorn worker killed")
      boom.backtrace = caller.dup

      Failbot.report(boom)
    end
  end
end
