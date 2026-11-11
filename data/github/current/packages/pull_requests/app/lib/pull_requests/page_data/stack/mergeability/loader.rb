# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module Mergeability
        class Loader
          include GitHub::ResilienceMixin
          include PullRequests::External::Domain::StatusChecks::Provider

          # The "pull_request" rule type covers many distinct failure modes
          # (awaiting approval, changes requested, unresolved threads, etc.)
          REVIEW_RULE_TYPE = "pull_request"

          # Rule failure types emitted by the rules engine that represent failing
          # status checks. When the only failed rules are these, we surface
          # the failure as ChecksFailing instead of FailingRules.
          STATUS_CHECK_RULE_TYPES = T.let(%w[
            required_status_checks
            required_workflow_status_checks
          ].freeze, T::Array[String])

          # Rule failure types emitted by the rules engine that represent failing
          # review approvals. These reasons signify the pull request is "waiting on a reviewer".
          # https://github.com/github/github/blob/master/app/platform/enums/pull_request_rule_failure_reason.rb
          PULL_REQUEST_AWAITING_REVIEW_REASONS = T.let(%w[
            code_owner_review_required
            last_push_approval_required
            more_reviews_required
            soc2_approval_process_required
          ].freeze, T::Array[String])

          # Rule failure types emitted by the rules engine that represent failing
          # rules not associated to the pull request "waiting on a reviewer".
          # https://github.com/github/github/blob/master/app/platform/enums/pull_request_rule_failure_reason.rb
          PULL_REQUEST_FAILING_RULES_REASONS = T.let(%w[
            changes_requested
            thread_resolution_required
          ].freeze, T::Array[String])

          class Data < T::Struct
            const :state, Symbol
            const :pull_request, ::PullRequest
            const :base_repository, ::Repository
            const :head_repository, T.nilable(::Repository)
            # Detailed status used by Stack::Mergeability::Payload.
            const :entry_status,
                  T.nilable(MergeBox::MergeRequirementsPayload::StackEntryStatus),
                  default: nil
          end

          sig do
            params(
              pull_request: PullRequest,
              current_user: T.nilable(User),
              merge_action: T.nilable(String),
              merge_method: T.nilable(String),
              bypass_requirements: T::Boolean,
            ).returns(Data)
          end
          def self.load(pull_request:, current_user:, merge_action:, merge_method:, bypass_requirements:)
            new(pull_request:, current_user:, merge_action:, merge_method:, bypass_requirements:).load
          end

          sig do
            params(
              pull_request: PullRequest,
              current_user: T.nilable(User),
              merge_action: T.nilable(String),
              merge_method: T.nilable(String),
              bypass_requirements: T::Boolean,
            ).void
          end
          def initialize(pull_request:, current_user:, merge_action:, merge_method:, bypass_requirements:)
            @pull_request = pull_request
            @current_user = current_user
            @merge_action = merge_action
            @merge_method = merge_method
            @bypass_requirements = bypass_requirements
          end

          sig { returns(Data) }
          def load
            distribution_time_metric = if status_checks_mergeability_ff_enabled?
              "pull_requests.stack.mergeability.status_checks_lookup"
            else
              "pull_requests.stack.mergeability.combined_status_state"
            end
            GitHub.dogstats.distribution_time(distribution_time_metric) do
              merge_requirements = PullRequest::MergeRequirements.new(
                @pull_request,
                @merge_action,
                @merge_method,
                @bypass_requirements,
                @current_user,
                skip_checks: status_checks_mergeability_ff_enabled? ? true : false,

                # NOTE: We don't need the stack condition in this context,
                # but this argument should probably be changed to `skip_stacks`
                # and defaulted to `false` when we graduate the feature flag.
                enable_stacks: false,
              )

              state = with_database_error_fallback(fallback: :unknown) { merge_requirements.state }

              entry_status = with_database_error_fallback(fallback: nil) { compute_entry_status(merge_requirements, state) }

              Data.new(
                state: state,
                pull_request: @pull_request,
                base_repository: T.must(@pull_request.base_repository),
                head_repository: @pull_request.head_repository,
                entry_status: entry_status,
              )
            end
          end

          private

          sig do
            params(
              merge_requirements: PullRequest::MergeRequirements,
              state: Symbol,
            ).returns(T.nilable(MergeBox::MergeRequirementsPayload::StackEntryStatus))
          end
          def compute_entry_status(merge_requirements, state)
            if state == :mergeable
              # An entry that's otherwise ready but has an active auto-merge
              # request (e.g. a "merge stack" was kicked off) is in the
              # Merging state until it actually merges.
              return MergeBox::MergeRequirementsPayload::StackEntryStatus::Merging if @pull_request.auto_merge_request.present?

              return MergeBox::MergeRequirementsPayload::StackEntryStatus::Ok
            end

            # Only reachable if :pull_request_stacks_status_checks_mergeability feature flag is enabled due to skip_checks: true when loading merge requirements
            if state == :mergeable_if_statuses_pass
              status_checks = with_database_error_fallback(fallback: nil) do
                status_checks_domain.for_pull_request(@pull_request, viewer: @current_user)
              rescue GitRPC::ObjectMissing
                nil
              end

              has_required_failure = T.let(false, T::Boolean)
              has_pending_requirement = T.let(false, T::Boolean)

              # Checks if there are status workflows pending approval
              if @pull_request.action_required_check_suites(head_sha: @pull_request.head_sha).any?
                has_pending_requirement = true
              end

              status_checks&.each do |status|
                break if has_required_failure
                next if !status.required?

                if StatusCheckConfig::FAILURE_AND_INCOMPLETE_STATES.include?(status.state)
                  has_required_failure = true
                elsif StatusCheckConfig::PENDING_STATES.include?(status.state)
                  has_pending_requirement = true
                end
              end

              # Status Checks aren't found or has a failing required status check
              if !status_checks || has_required_failure
                return MergeBox::MergeRequirementsPayload::StackEntryStatus::ChecksFailing
              # Some required Status Checks are pending
              elsif has_pending_requirement
                return MergeBox::MergeRequirementsPayload::StackEntryStatus::ChecksPending
              # All required Status Checks are passing
              else
                return MergeBox::MergeRequirementsPayload::StackEntryStatus::Ok
              end
            end

            conditions = merge_requirements.async_conditions.sync

            # Merge conflicts take precedence over rule failures.
            conflict_type = MergeBox::MergeRequirementsPayload::MergeConditionType::PullRequestMergeConflictState
            if conditions.any? { |c| c.merge_condition_type == conflict_type && c.failed? }
              return MergeBox::MergeRequirementsPayload::StackEntryStatus::MergeConflicts
            end

            # Inspect the rules engine for the kind of rule that's failing.
            rules = T.cast(
              conditions.find { |c| c.is_a?(::MergeConditions::PullRequestRules) },
              T.nilable(::MergeConditions::PullRequestRules),
            )
            rule_suite = rules&.rule_suite
            failed_rule_types = rule_suite&.failed_rule_types || []

            failure_reasons = if rule_suite && failed_rule_types.include?(REVIEW_RULE_TYPE)
              RulesEngine::RuleRollups::PullRequestRollupMetadata.new(rule_suite)
            end&.payload&.failureReasons

            if awaiting_approval?(failure_reasons)
              return MergeBox::MergeRequirementsPayload::StackEntryStatus::AwaitingApproval
            end

            # Check for failing status checks
            if failed_rule_types.any? && (failed_rule_types - STATUS_CHECK_RULE_TYPES).empty?
              return MergeBox::MergeRequirementsPayload::StackEntryStatus::ChecksFailing
            end

            # Handle any other failed rules
            if failed_rule_types.any?
              return MergeBox::MergeRequirementsPayload::StackEntryStatus::FailingRules
            end

            if !status_checks_mergeability_ff_enabled?
              # No rule failures — surface status-check state.
              case combined_status_state
              when :failure then MergeBox::MergeRequirementsPayload::StackEntryStatus::ChecksFailing
              when :pending then MergeBox::MergeRequirementsPayload::StackEntryStatus::ChecksPending
              else
                # Fallback for unmergeable PRs blocked by a non-rule-suite, non-conflict
                # condition (e.g. PullRequestState/PullRequestRepoState/PullRequestUserState/
                # PullRequestMergeMethod). We don't have a more specific status for these,
                # so treat them as a generic blocking failure.
                MergeBox::MergeRequirementsPayload::StackEntryStatus::BlockedStack
              end
            else

              # Fallback for unmergeable PRs blocked by a non-rule-suite, non-conflict
              # condition (e.g. PullRequestState/PullRequestRepoState/PullRequestUserState/
              # PullRequestMergeMethod). We don't have a more specific status for these,
              # so treat them as a generic blocking failure.
              MergeBox::MergeRequirementsPayload::StackEntryStatus::BlockedStack
            end
          end

          sig { returns(T::Boolean) }
          def status_checks_mergeability_ff_enabled?
            FeatureFlag.vexi.enabled?(
              :pull_request_stacks_status_checks_mergeability,
              @pull_request.base_repository,
              default: false,
            )
          end

          # Returns one of :success | :failure | :pending | :unknown for the
          # entry's combined commit status using status check rollup info
          sig { returns(Symbol) }
          def combined_status_state
            combined = @pull_request.combined_status
            case combined.state.to_s
            when "success" then :success
            when "failure", "error" then :failure
            when "pending" then :pending
            else :unknown
            end
          rescue
            :unknown
          end

          sig { params(failure_reasons: T.nilable(T::Array[String])).returns(T::Boolean) }
          def awaiting_approval?(failure_reasons)
            return false if failure_reasons.nil?
            return false if failure_reasons.empty?
            return false if failure_reasons.intersect?(PULL_REQUEST_FAILING_RULES_REASONS)

            failure_reasons.intersect?(PULL_REQUEST_AWAITING_REVIEW_REASONS)
          end
        end
      end
    end
  end
end
