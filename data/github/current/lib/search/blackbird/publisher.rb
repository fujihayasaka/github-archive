# typed: true
# frozen_string_literal: true

module Search
  module Blackbird
    module Publisher
      # internal: allows selection of the event publisher appropriate for each call site
      # by applying an override field to the event payload. If the publisher field is
      # not supplied, the standard (analytics-oriented) publisher is applied. Example:
      #
      # payload = {
      #   change: :VISIBILITY_CHANGED,
      #   foo: "bar",
      #   ...
      #   publisher: :low_latency,
      # }
      #
      # GlobalInstrumenter.instrument("search_indexing.repository_changed", payload)
      def self.override(payload)
        selector = payload.fetch(:publisher, :standard)

        case selector.to_sym
        when :low_latency
          GitHub.low_latency_hydro_publisher
        when :sync
          GitHub.sync_hydro_publisher
        else
          GitHub.hydro_publisher
        end
      end
    end
  end
end
