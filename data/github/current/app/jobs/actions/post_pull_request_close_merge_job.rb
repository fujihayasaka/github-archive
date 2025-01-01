# typed: strict
# frozen_string_literal: true

module Actions
  class PostPullRequestCloseMergeJob < ApplicationJob
    extend T::Sig

    queue_as :actions

    # Wait for replication lag
    use_replicas ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::RepositoriesActionsChecks,
      allow_replication_lag: [
        ApplicationRecord::Repositories,
        ApplicationRecord::Collab,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Spokes
      ]

    retry_on_dirty_exit

    discard_on ActiveJob::DeserializationError do |_job, error|
      Failbot.report(error)
    end

    sig { params(pull_request: PullRequest).void }
    def perform(pull_request)
      return stat("not_merged_or_closed") if pull_request.open?

      result = "no_action_required_check_suites"

      pull_request.changed_commits.each do |commit|
        check_suites = pull_request.action_required_check_suites(head_sha: commit.oid)

        unless check_suites.blank?
          result = "action_required_check_suites_found"
          check_suites.each do |cs|
            Actions::DeleteActionRequiredCheckSuiteJob.perform_later(cs.id, cs.repository_id, cs.github_app_id)
          end
        end
      end

      stat(result)
    end

    sig { params(result: String).void }
    def stat(result)
      GitHub.dogstats.increment("actions.post_pull_request_close_merge_job", tags: ["result:#{result}"])
    end
  end
end
