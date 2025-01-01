# typed: false
# frozen_string_literal: true

require "pitchfork"

class Pitchfork::HttpServer
  # Monkey patch to add logging to the build_app method
  def build_app_with_log!
    t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    logger.info "master build_app=start"
    profile_boot do
      build_app_without_log!
    end
    duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1) * 1000
    logger.info "master build_app=end duration=#{'%.2f' % duration}"

    GitHub::BootMetrics.record_state("unicorn.build_app", duration: duration)
  end
  alias_method :build_app_without_log!, :build_app!
  alias_method :build_app!, :build_app_with_log!

  def profile_boot
    if ENV["PROFILE_APP_BUILD"]
      require "stackprof"
      type = ENV["PROFILE_APP_BUILD"].to_sym

      unless [:object, :wall, :cpu].include?(type)
        type = :wall
      end

      filename = "tmp/stackprof-#{type}-#{$$}.dump"
      StackProf.run(mode: type, out: filename) do
        yield
      end
      logger.info "Profile written to #{filename}"
      Process.kill("QUIT", @master_pid)
    else
      yield
    end
  end
end
