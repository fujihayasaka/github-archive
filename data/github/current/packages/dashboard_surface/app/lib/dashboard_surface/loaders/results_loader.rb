# typed: strict
# frozen_string_literal: true

module DashboardSurface
  module Loaders
    class ResultsLoader
      class DeferredData < T::Struct
        const :pull_requests, T::Array[PullRequest]
        const :combined_statuses, T::Hash[Integer, T.nilable(CombinedStatus)]
        const :review_decisions, T::Hash[Integer, T.nilable(Symbol)]

        sig { returns(DeferredData) }
        def self.empty
          new(pull_requests: [], combined_statuses: {}, review_decisions: {})
        end
      end

      # The issues array has already been filtered by the `ConditionalIssueQuery` to limit the query to repos the user can access,
      # see: https://github.com/github/github/blob/da9efb94ae237508f22ca6e85a751ff63a304059/packages/issues/app/models/search/queries/conditional_issue_query.rb#L242-L245
      sig { params(issues: T::Array[Issue], current_user: T.nilable(User), exclude_prefills: T::Array[Symbol]).returns(T::Array[PullRequest]) }
      def self.main_content_from(issues:, current_user:, exclude_prefills: [])
        if current_user
          read_issues = Issue.read_for(current_user, issues)

          issues.each do |issue|
            issue.read_by_current_user = read_issues.include?(issue.id)
          end
        end

        IssuePrefiller.prefill(issues, current_user: current_user, exclude_prefills: exclude_prefills)
        pull_requests = issues.map(&:pull_request).compact
        PullRequest.prefill_associations(pull_requests, issues: issues)

        # Prefill agent-attributed users to avoid an N+1 in PullRequestResult.
        # Gated on the same per-viewer flag the payload uses so disabled traffic
        # pays no cost.
        if current_user && FeatureFlag.vexi.enabled?("agent_author_search_expansion_ui_pulls", current_user, default: false)
          GitHub::PrefillAssociations.prefill_associations(pull_requests, { pull_request_copilot_attributions: :user })
        end

        if PullRequests::Stacks.enabled?(pull_requests.filter_map(&:repository).uniq)
          GitHub::PrefillAssociations.prefill_associations(pull_requests, :stack)
        end

        pull_requests
      end

      # The issues array has already been filtered by the `ConditionalIssueQuery` to limit the query to repos the user can access,
      # see: https://github.com/github/github/blob/da9efb94ae237508f22ca6e85a751ff63a304059/packages/issues/app/models/search/queries/conditional_issue_query.rb#L242-L245
      #
      # If we decide to pass params instead re-running the search query, we will need to apply filtering,
      # see: PullRequestReviewDecisionsController and https://github.com/github/github/pull/215529/files#r845614700, for context.
      # Alternatively, we could batch deferred requests by repository and run CAP checks,
      # see: ChecksStatusController#rollups
      sig { params(issues: T::Array[Issue], current_user: T.nilable(User)).returns(DeferredData) }
      def self.deferred_content_from(issues:, current_user:)
        IssuePrefiller.prefill(issues, only_prefill: [:pull_request], current_user: current_user)
        GitHub::PrefillAssociations.prefill_batch_method(issues, :repository)

        pull_requests = issues.map(&:pull_request).compact
        statuses = load_combined_statuses_for(pull_requests)
        review_decisions = load_review_decisions_for(pull_requests, current_user)
        DeferredData.new(combined_statuses: statuses, review_decisions: review_decisions, pull_requests: pull_requests)
      end

      sig { params(pull_requests: T::Array[PullRequest]).returns(T::Hash[Integer, T.nilable(CombinedStatus)]) }
      private_class_method def self.load_combined_statuses_for(pull_requests)
        object_promises = pull_requests.map do |pull|
          key = pull.id
          commit_oid = pull.head_sha
          Platform::Loaders::CombinedStatusOverview.load(T.must(pull.issue).repository, commit_oid)
            .then do |rows|
              states = rows.map { |row| row["conclusion"] }
              state = ::StatusCheckRollup.rollup_state(states)
              short_text = Platform::Loaders::CombinedStatusOverview.short_text(rows)
              # short text is "#{successful_count} / #{total_count} checks OK"
              next [key, nil] if short_text.nil?

              combined_status = ::CombinedStatus.new(T.must(pull.issue).repository, commit_oid, platform_type_name: "StatusCheckRollup", state: state, short_text: short_text)
              [key, combined_status]
            end
        end

        Promise.all(object_promises).sync.to_h
      end

      # Returns :changes_requested, :approved, :review_required, or nil.
      sig { params(pull_requests: T::Array[PullRequest], current_user: T.nilable(User)).returns(T::Hash[Integer, T.nilable(Symbol)]) }
      private_class_method def self.load_review_decisions_for(pull_requests, current_user)
        GitHub::PrefillAssociations.prefill_batch_method(pull_requests, :base_branch_rule_evaluator)
        PullRequest.prefill_review_decisions(pull_requests, current_user)

        pull_requests.each_with_object({}) do |pull, decisions|
          decisions[pull.id] = pull.review_decision(viewer: current_user)
        end
      end
    end
  end
end
