# typed: false
# frozen_string_literal: true

require "github/timer"

module GitHub
  module TimeoutAndMeasure
    include GitHub::Timer

    def timeout_and_measure(timeout_in_s, stat_prefix)
      measure(stat_prefix) do
        begin
          timeout(timeout_in_s.to_i) do
            yield
          end
        rescue GitHub::Timer::Error
          GitHub.dogstats.increment("#{stat_prefix}.timeout")
          GitHub.stats.increment("#{stat_prefix}.timeout") if GitHub.enterprise?
          nil
        end
      end
    end

    def measure(stat_prefix)
      start = Time.now
      yield
    ensure
      duration = Time.now - start
      GitHub.stats.timing(stat_prefix, duration) if GitHub.enterprise?
      GitHub.dogstats.timing(stat_prefix, duration)
    end

  end
end
