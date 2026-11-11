# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class SeatEmissionHydroPublisher
      include GitHub::Memoizer

      sig { params(owner: T.any(::Organization, ::Business)).void }
      def initialize(owner:)
        @owner = T.let(owner, T.any(::Organization, ::Business))
      end

      sig { params(stat: String, block: T.proc.params(publisher: Hydro::Publisher, publisher_tag: String).void).void }
      def publish_with_timing(stat, &block)
        GitHub.dogstats.time(stat, tags: [publisher_tag]) do
          block.call(publisher, publisher_tag)
        end
      end

      sig { returns(Hydro::Publisher) }
      def publisher
        if use_sync_hydro_publisher?
          GitHub.sync_hydro_publisher
        else
          GitHub.hydro_publisher
        end
      end

      sig { returns(String) }
      def publisher_tag
        "publisher:#{use_sync_hydro_publisher? ? 'sync' : 'async'}"
      end

      private

      sig { returns(T::Boolean) }
      memoize def use_sync_hydro_publisher?
        FeatureFlag.vexi.enabled?(:copilot_emissions_sync_hydro_publisher, @owner, default: false)
      end
    end
  end
end
