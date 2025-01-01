# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdatedBackfillPullRequestsStatus < Base
      iterate_over :database_table, params: {
        model_class: PullRequest,
        columns: %i[id repository_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        if dry_run?
          log("Iterating over #{items.count} pull requests, start ID: #{items.keys.first} end ID: #{items.keys.last}")

          updated_count = T.let(0, Integer)

          items.each do |pull_request_id, results_hash|
            repository_id = results_hash[:repository_id]

            updated_count += PullRequest.where(repository_id: repository_id, id: pull_request_id).joins(:issue).
              where("issues.state <> pull_requests.status").or(PullRequest.where(repository_id: repository_id, id: pull_request_id, status: nil)).count
          end

          if updated_count > 0
            log("Would update mismatched or nil `status` for #{updated_count} pull requests, start ID: #{items.to_a.first} end ID: #{items.to_a.last}")
          end

          log("Would not have updated #{items.count - (updated_count)} pull requests, start ID: #{items.to_a.first} end ID: #{items.to_a.last}")
        else
          log("Iterating over #{items.count} pull requests, start ID: #{items.keys.first} end ID: #{items.keys.last}")

          updated_count = T.let(0, Integer)

          items.each do |pull_request_id, results_hash|
            repository_id = results_hash[:repository_id]

            write_to(model_class: PullRequest) do
              PullRequest.transaction do
                state = Issue.lock("LOCK IN SHARE MODE").where(repository_id: repository_id, pull_request_id: pull_request_id).pick(:state)
                updated_count += PullRequest.where(repository_id: repository_id, id: pull_request_id).where.not(status: state).or(
                  PullRequest.where(repository_id: repository_id, id: pull_request_id, status: nil)
                ).update_all(status: state)
              end
            end
          end

          if updated_count > 0
            log("Successfully updated `status` for #{updated_count} pull requests, start ID: #{items.to_a.first} end ID: #{items.to_a.last}")
          else
            log("Did not update `status` for #{items.count} pull requests, start ID: #{items.to_a.first} end ID: #{items.to_a.last}")
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

  GitHub::Transitions::UpdatedBackfillPullRequestsStatus.new(args).run
end
