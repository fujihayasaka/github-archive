# typed: true
# frozen_string_literal: true

module RuleEngine
  module Rules
    class ThreadResolutionRule < RefUpdateRule

      def initialize
        super(rule_name: "required_review_thread_resolution",
              display_name: "Require conversation resolution before merging",
              description: "When enabled, all conversations on code must be resolved before a pull request can be merged into a branch that matches this rule.")
      end

      sig { override.params(rule_config: RepositoryRuleConfiguration).returns(T::Array[Symbol]) }
      def ignore_update_types(rule_config)
        # ignore updates to pull requests in the merge queue, and branch deletions/creations (there would be no PR)
        [:creation, :deletion, :ref_in_merge_queue]
      end

      # The thread resolution policy has no configuration: return the same result for each configuration
      sig { override.params(context: RuleEvaluationContext, policies_by_ref_update: T::Hash[Git::Ref::Update, T::Array[RepositoryRuleConfiguration]]).returns(T::Array[RuleRun]) }
      def bulk_evaluate(context, policies_by_ref_update)
        repository = context.repository
        updates = policies_by_ref_update.keys

        commit_oids = updates.each_with_object([]) do |update, accumulator|
          if update.after_commit.merge_commit? && update.after_commit.parent_oids.include?(update.before_oid)
            accumulator.concat(update.after_commit.parent_oids - [update.before_oid])
          end
        end

        commits = Platform::Loaders::GitObject.load_all(repository, commit_oids, expected_type: "commit").sync
        commits_by_oid = commit_oids.zip(commits).to_h

        policies_by_ref_update.each_with_object([]) do |(update, configs), rule_runs|
          passed = T.let(true, T::Boolean)
          pull_request = update.try(:pull_request)

          if pull_request.present?
            passed = all_pull_request_review_threads_resolved?(pull_request)
          elsif update.after_commit.merge_commit? && update.after_commit.parent_oids.include?(update.before_oid)
            relevant_parents = update.after_commit.parent_oids - [update.before_oid]
            passed = relevant_parents.all? { |parent_oid| validate_review_threads_are_resolved(repository, parent_oid) }
          else
            passed = validate_review_threads_are_resolved(repository, update.after_oid)
          end

          if passed
            rule_runs.concat(configs.map { |config| RuleRun.success(rule_config: config, ref_update: update) })
          else
            rule_runs.concat(configs.map do |config|
              RuleRun.failure(rule_config: config, ref_update: update, message: "All comments must be resolved.")
            end)
          end
        end
      end

      def validate_review_threads_are_resolved(repository, commit_oid)
        pull_requests = repository.pull_requests.open_pulls.where(head_sha: commit_oid)

        if pull_requests.length > 1
          GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.required_review_thread_resolution_multiple_pull_requests_checked")
        elsif pull_requests.length == 1
          GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.required_review_thread_resolution_one_pull_request_checked")
        end

        pull_requests.all? { |pull_request| all_pull_request_review_threads_resolved?(pull_request) }
      end

      def all_pull_request_review_threads_resolved?(pull_request)
        review_threads = PullRequestReviewThread.non_pending_review_threads(pull_request.id)
          .includes(:pull_request_review)
        # Not all threads count as conversations. Non conversation threads should not be counted towards the branch protection policy.
        review_threads = review_threads.filter(&:conversation?)
        review_threads.all? { |review_thread| review_thread.resolved? }
      end
    end
  end
end
