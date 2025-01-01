# typed: true
# frozen_string_literal: true

module Platform
  module CatalogServiceStats

    # returns a Hash of catalog service name to the total elapsed time spent in that service
    # ex:
    # {
    #   "github/roles_and_permissions" => { "elapsed_time_ms" => 100 },
    #   "github/notifications" => { "elapsed_time_ms" => 232 }
    # }
    def self.metrics_by_service(trace)
      return {} unless trace&.respond_to?(:step_timings)

      steps_by_service = trace.step_timings&.group_by(&:catalog_service)
      return {} unless steps_by_service

      steps_by_service.to_h do |service, steps|
        elapsed_time_ms = (steps.sum(&:duration) * 1000).round
        stats = {
          elapsed_time_ms: elapsed_time_ms
        }
        [service, stats]
      end
    end
  end
end
