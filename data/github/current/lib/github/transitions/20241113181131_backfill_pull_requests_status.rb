# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

module GitHub
  module Transitions
    class BackfillPullRequestsStatus < Base
      iterate_over :database_table, params: {
        model_class: Issue,
        columns: %i[pull_request_id state],
        conditions: "pull_request_id IS NOT NULL",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        cases = []
        pull_request_ids = items.map { |_, columns| columns[:pull_request_id] }

        if dry_run?
          log("Would update `status` for #{pull_request_ids.count} pull requests, start ID: #{pull_request_ids.first} end ID: #{pull_request_ids.last}")
        else
          log("Will update `status` for #{pull_request_ids.count} pull requests, start ID: #{pull_request_ids.first} end ID: #{pull_request_ids.last}")

          items.each do |_, columns|
            cases << PullRequest.sanitize_sql_for_conditions(["WHEN :id THEN :value", { id: columns[:pull_request_id], value: columns[:state] }])
          end

          update_query = "status = CASE id #{cases.join(" ")} END"
          updated_count = T.let(0, Integer)

          write_to(model_class: PullRequest) do
            updated_count = PullRequest.where(id: pull_request_ids).update_all(update_query)
          end

          # Verify that we did the correct updates
          if updated_count == pull_request_ids.count
            log("Successfully updated #{updated_count} pull requests, start ID: #{pull_request_ids.first} end ID: #{pull_request_ids.last}")
          else
            log("FAIL: updated: #{updated_count}, target: #{pull_request_ids.count}, start ID: #{pull_request_ids.first} end ID: #{pull_request_ids.last}")
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

  GitHub::Transitions::BackfillPullRequestsStatus.new(args).run
end
