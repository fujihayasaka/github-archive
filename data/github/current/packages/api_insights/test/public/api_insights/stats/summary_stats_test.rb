# typed: true
# frozen_string_literal: true

require "test_helper"

module ApiInsights::Stats
  class SummaryStatsTest < GitHub::TestCase
  end

  class TestableSummaryStats < SummaryStats
    def initialize
      now = Time.now.utc
      super 1, now - 1.day, now
    end

    def query
      super
    end
  end
end
