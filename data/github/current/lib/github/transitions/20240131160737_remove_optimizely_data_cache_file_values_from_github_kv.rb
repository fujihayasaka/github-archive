# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class RemoveOptimizelyDataCacheFileValuesFromGithubKv < Base

      sig { override.void }
      def perform
        # Review lab shares production's KV.
        %w[optimizely-datafile-production optimizely-datafile-review_lab optimizely-datafile-last-modified-production optimizely-datafile-last-modified-review_lab optimizely-datafile-size-production optimizely-datafile-size-review_lab].each do |key|
          key_result = GitHub.kv.get(key).value { nil }
          if key_result.nil?
            log "Could not find value for #{key}"
          else
            if dry_run?
              log "Tried to delete #{key}, but dry run is enabled. Skipping..."
            else
              ActiveRecord::Base.connected_to(role: :writing) do
                GitHub.kv.del(key)
              end

              log"Removed #{key}"
            end
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::RemoveOptimizelyDataCacheFileValuesFromGithubKv.new(args).run
end
