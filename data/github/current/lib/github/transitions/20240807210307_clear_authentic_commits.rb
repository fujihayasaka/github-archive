# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ClearAuthenticCommits < Base
      BATCH_SIZE = 1_000

      sig { override.void }
      def perform
        total_count = T.let(AuthenticCommit.count, Integer)
        if dry_run?
          log("would delete #{total_count} total records")
          return
        end

        # can't use a naive DELETE FROM ... LIMIT approach because that would make cross-shard deletes, which
        # is not supported by vitess

        network_ids = AuthenticCommit.distinct.pluck(:network_id)

        network_ids.each do |id|
          network_id_count = AuthenticCommit.where(network_id: id).count
          num_batches = (network_id_count.to_f / BATCH_SIZE).ceil

          num_batches.times do
            write_to(model_class: AuthenticCommit) do
              AuthenticCommit.where(network_id: id).limit(BATCH_SIZE).delete_all
            end
          end
        end

        log("finished, #{AuthenticCommit.count} records remaining in table")
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

  GitHub::Transitions::ClearAuthenticCommits.new(args).run
end
