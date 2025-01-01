# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    class Stats
      module Tracker
        class CommandPalette
          extend Tracker

          sig do
            override.params(
              dogstats: T.untyped,
              env: T.untyped,
              stats: T::Hash[Symbol, T.untyped],
              tags_cache: GitHub::DatadogTagsCache,
            ).void
          end
          def self.track(dogstats, env, stats, tags_cache)
            return unless stats[:controller] == "command_palette_providers"

            tags = [
              tags_cache[TaggingHelper::STATUS_TAG],
              tags_cache[TaggingHelper::STATUS_RANGE_TAG],
              tags_cache[TaggingHelper::CONTROLLER_TAG],
              tags_cache[TaggingHelper::COMMAND_PALETTE_PROVIDER_NAME_TAG],
            ].compact

            dogstats.distribution("request.command_palette.time", stats[:real_ms], tags: tags)
          end
        end
      end
    end
  end
end
