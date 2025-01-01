# typed: true
# frozen_string_literal: true

class AqueductLiteProcessHelper
  include Singleton
  extend T::Sig

  PORT = 18081
  # The override used in tests is explained in lib/active_support/testing/parallelization/worker.rb.
  WAIT_TIMEOUT_SECONDS = (ENV["TEST_SERVICES_STARTUP_TIMEOUT"] || "10").to_i
  OUT = "tmp/aqueduct-lite.out.log"
  ERR = "tmp/aqueduct-lite.err.log"

  class << self
    delegate :ensure_jobs_can_enqueue, to: :instance
  end

  def ensure_jobs_can_enqueue
    return if listening?

    start
  end

  private

  attr_reader :pid

  # May only be set once
  def pid=(val)
    if @pid
      raise ArgumentError, "@pid is already #{@pid.inspect}, may not be clobbered with #{val.inspect}"
    end
    @pid = val
  end

  def start
    if (s = status) != Status::Stopped
      raise "attempted to start a process in invalid state #{s.inspect}"
    end

    at_this_process_exit { stop }

    self.pid = Process.spawn(
      Hash.new,
      "bin/aqueduct-lite-server",
      out: OUT,
      err: ERR,
      chdir: Rails.root.to_s,
    )

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) - start < WAIT_TIMEOUT_SECONDS
      if listening?
        return true
      end
      sleep 0.01
    end
    raise_timeout
  end

  def raise_timeout
    err = IO.readlines(ERR).last(100).join
    out = IO.readlines(OUT).last(100).join
    detail = "status: #{status.inspect}\nstderr:\n#{err}\nstdout:\n#{out}"
    raise "aqueduct-lite is not listening on #{PORT} after #{WAIT_TIMEOUT_SECONDS} seconds.\n#{detail}"
  end

  def stop
    if status.running?
      Process.kill "TERM", pid
      Process.waitpid(pid)
    end
    @wait_status = nil
    @pid = nil
  end

  def listening?
    TCPSocket.open("127.0.0.1", PORT).close
    true
  rescue Errno::ECONNREFUSED
    false
  end

  def at_this_process_exit
    original_pid = Process.pid
    at_exit do
      next unless Process.pid == original_pid
      yield
    end
  end

  # The current state of the supervised aqueduct-lite process.
  class Status < T::Enum
    enums do
      # Process is healthy
      RunningAndListening = new
      # Process appears to be running but TCP connect failed
      RunningNotListening = new
      # `@pid` ivar not set, which should mean we either never started or have
      # intentionally stopped already.
      Stopped = new
      # Process unexpectedly exited with healthy status
      ExitZero = new
      # Process unexpectedly exited with unhealthy status
      ExitNonzero = new
    end

    def healthy?
      self == RunningAndListening
    end

    def running?
      self == RunningAndListening || self == RunningNotListening
    end
  end

  sig { returns Status }
  def status
    return Status::Stopped if pid.nil?
    case (s = wait_status)
    when Process::Status # exited
      s.success? ? Status::ExitZero : Status::ExitNonzero
    when NilClass # running
      listening? ? Status::RunningAndListening : Status::RunningNotListening
    else
      T.absurd(s)
    end
  end

  # An exited process can only be waited on successfully once, so we have to
  # memoize the result to remember it. WNOHANG causes this to return nil if pid
  # is running, so this is the odd case where we _want_ the no-memoizing-nil
  # behavior.
  sig { returns T.nilable(Process::Status) }
  def wait_status
    @wait_status ||= begin
      _, status = Process.wait2(self.pid, Process::WNOHANG)
      status
    end
  end
end
