# typed: true
# frozen_string_literal: true

class Issue
  # Primary interface into searching metrics.
  class SearchMetrics
    def self.track(metric, tags: [])
      timer = Timer.start
      result = yield
      timer.stop
      GitHub.dogstats.distribution(metric, timer.elapsed_ms, tags: tags.flatten.uniq)
      result
    end
  end
end
