# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "active_job"
require "active_job/scheduled_job"

require "minitest/autorun"

require "debug"

module TestHelpers

  class FakeTimerDaemon
    attr_reader :schedules
    attr_accessor :raise_on_schedule

    def initialize
      @schedules = {}
    end

    def schedule(name, interval, options = {}, &block)
      raise "FakeTimerDaemon#schedule raised" if raise_on_schedule

      @schedules[name] = [interval, options]
    end
  end
end
