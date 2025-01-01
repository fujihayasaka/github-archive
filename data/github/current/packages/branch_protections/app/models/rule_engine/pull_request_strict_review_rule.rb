# typed: true
# frozen_string_literal: true

module RuleEngine
  class PullRequestStrictReviewRule
    include Scientist
    include Repositories::Domain::Provider

    # Uncomment these when RuleEngine::PullRequestReviewRule is removed
    # SOC2_REPOS = %w(github/github).freeze
    # SOC2_REVIEWERS_TEAM_PATTERN = /-reviewers\z/.freeze

    # Default settings when running in webpage, etc
    DEFAULT_LAST_PUSHER_BATCH_SIZE = 4
    DEFAULT_LAST_PUSHER_TIMEOUT = 5.seconds

    # Default settings when finding the last pusher from a job
    DEFAULT_LAST_PUSHER_BATCH_SIZE_JOB_AGENT = 10
    DEFAULT_LAST_PUSHER_TIMEOUT_JOB_AGENT = 40.seconds

    DISMISS_STALE_APPROVALS_RATE_LIMIT = 5.minutes

    # Public: Check the pull request review policy for one or more ref updates for protected branches
    # Returns a list of Decisions.
    # This method is only called by tests, and is redundant with self.check_policies
    sig do params(
      repository: Repository,
      ref_updates: T::Array[Git::Ref::Update],
      policy_evaluator_by_refname: T::Hash[String, BranchRuleEvaluator],
      actor: T.nilable(RuleEngine::Types::Actor))
      .returns(T::Array[PullRequestReviewRule::Decision])
    end
    def self.check(repository, ref_updates, policy_evaluator_by_refname, actor:)
      policies_by_refname = policy_evaluator_by_refname.map do |refname, policy_evaluator|
        [refname, policy_evaluator.pull_request_policies]
      end.to_h

      new(repository, ref_updates, policies_by_refname, actor: actor).check
    end

    # Public: Check the pull request review policy for one or more ref updates for pull request policies
    #
    # repository                       - The Repository, Gist, or Unsullied::Wiki whose refs
    #                                    are being updated
    # policies_by_refname              - Hash with Git::Ref::Updates as keys and an array of relevant `RepositoryRuleConfiguration`s as values
    # actor                            - The User or PublicKey attempting to make an update
    # server_merge                    - Is this a server generated branch merge?
    #
    # Returns a list of Decisions
    # TODO: This does the same thing as self.check, and is only called in a few places. We should remove one of them.
    sig do params(
      repository: Repository,
      ref_updates: T::Array[Git::Ref::Update],
      policies_by_refname: T::Hash[String, T::Array[RepositoryRuleConfiguration]],
      actor: T.nilable(RuleEngine::Types::Actor))
      .returns(T::Array[PullRequestReviewRule::Decision])
    end
    def self.check_policies(repository, ref_updates, policies_by_refname, actor:)
      new(repository, ref_updates, policies_by_refname, actor: actor).check
    end

    # Public: Check the pull request review policy for a single Pull Request.
    # Returns a promise resolving to a single Decision.
    sig do params(
      pull_request: PullRequest,
      actor: T.nilable(RuleEngine::Types::Actor),
      ref_update: RuleEngine::Types::NullableRefUpdate,
      policy_evaluator: T.nilable(BranchRuleEvaluator))
      .returns(Promise[PullRequestReviewRule::Decision])
    end
    def self.async_check_pull_request(pull_request:, actor:, ref_update:, policy_evaluator: nil)
      policy_evaluator ||= pull_request.base_branch_rule_evaluator
      pr_policies = policy_evaluator&.pull_request_policies

      new(T.must(pull_request.repository), [ref_update], { ref_update.refname => pr_policies }, actor: actor, pull_request: pull_request).
        async_check_pull_request
    end

    # Public: Constructor
    sig do params(
      repository: Repository,
      ref_updates: T::Array[RuleEngine::Types::NullableRefUpdate],
      policies_by_refname: T::Hash[String, T::Array[RepositoryRuleConfiguration]],
      actor: T.nilable(RuleEngine::Types::Actor),
      pull_request: T.nilable(PullRequest),
      server_merge: T::Boolean,
      cli_merge: T::Boolean
    ).void
    end
    def initialize(repository, ref_updates, policies_by_refname, actor:, pull_request: nil, server_merge: false, cli_merge: false)
      @repository = repository
      @ref_updates = ref_updates
      @policies_by_refname = policies_by_refname
      @actor = actor
      @server_merge = server_merge
      @cli_merge = cli_merge

      @single_pull_request = pull_request
      if !@single_pull_request && @ref_updates.size == 1
        @single_pull_request = @ref_updates.first.try(:pull_request)
      end
    end

    # Check the policy for a single Pull Request, and return a Decision.
    # Returns a promise resolving to a single Decision
    sig { returns(Promise[PullRequestReviewRule::Decision]) }
    def async_check_pull_request
      ref_update = ref_updates.first
      rule_configs = find_pull_request_policies(ref_update)

      if rule_configs.none?
        # No PR policies apply -- don't bother prefetching review associations
        single_pull_request.async_latest_enforced_reviews(writers_only: true).then do |reviews|
          decision_approved_no_policies_found(ref_update, reviews)
        end
      else
        # Prefetch a bunch of DB objects which are often needed to make policy decisions
        single_pull_request.async_latest_enforced_reviews_with_prefetch(writers_only: true).then do
          process_policies(ref_update, single_pull_request, rule_configs)
        end
      end
    end

    # For a list of ref updates, find all candidate pull requests and check each PR against all policies
    sig { returns(T::Array[RuleEngine::PullRequestReviewRule::Decision]) }
    def check
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.check", tags: ["strict:true"]) do
        ref_updates.map do |ref_update|
          rule_configs = find_pull_request_policies(ref_update)

          if rule_configs.none?
            # No policies apply to the branch this ref_update is pushing to
            decision_approved_no_policies_found(ref_update,
              single_pull_request&.latest_enforced_reviews(writers_only: true))
          else
            candidate_prs = if single_pull_request
              [single_pull_request]
            else
              # In this case, ref_updates are being pushed directly to possibly-protected branches. The only way this
              # ref_update can get approved is if after_commit is valid for an existing PR, either a 2-parent merge
              # with parents being the PR's target branch HEAD and the PR's source branch HEAD, or a direct push of
              # the source branch HEAD to the target branch (if the PR is fast-forwardable).
              verify_pushed_tree =
                rule_configs.any? { |c| c.param("dismiss_stale_reviews_on_push") } ||
                rule_configs.any? { |c| check_last_pusher(c) }

              candidate_pull_requests_for_push(T.cast(ref_update, Git::Ref::Update), verify_pushed_tree)
            end

            if candidate_prs.empty?
              # This ref_update doesn't match any open PRs at all. It can't be approved.
              decision_rejected_no_pull_request(ref_update, rule_configs)
            else
              decision = T.let(nil, T.nilable(PullRequestReviewRule::Decision))
              approved_decision = T.let(nil, T.nilable(PullRequestReviewRule::Decision))

              pr_policy_decisions = candidate_prs.each do |pull_request|
                decision = process_policies(ref_update, pull_request, rule_configs)

                if decision.rules_fulfilled?
                  approved_decision ||= decision
                  approved_decision.compliant_pull_request_ids << pull_request.id
                end
              end

              # Return the first approved or the last rejected decision.
              final_decision = approved_decision || decision
              T.must(final_decision).considered_pull_request_ids.concat(candidate_prs.map(&:id))
              final_decision
            end
          end
        end
      end
    end

    private

    sig { returns(Repository) }
    attr_reader :repository

    attr_reader :ref_updates, :policies_by_refname, :actor, :single_pull_request

    # Private: check all policies for a single pull request
    sig do params(
      ref_update: RuleEngine::Types::NullableRefUpdate,
      pull_request: PullRequest,
      rule_configs: T::Array[RepositoryRuleConfiguration])
      .returns(PullRequestReviewRule::Decision)
    end
    def process_policies(ref_update, pull_request, rule_configs)
      GitHub.dogstats.distribution("repository_rules_engine.rule.pull_request.process_policies.rule_configs", rule_configs.count, tags: ["strict:true"])
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.process_policies", tags: ["strict:true"]) do
        policy_commit_oid = T.must(pull_request.head_sha)
        dismiss_stale_reviews = rule_configs.any? { |c| c.param("dismiss_stale_reviews_on_push") }
        dismiss_stale_reviews_enforce = rule_configs.any? do |c|
          c.param("dismiss_stale_reviews_on_push") && (c.provider_name == "protected_branch" || c.repository_ruleset&.enabled?)
        end
        last_push_approval = rule_configs.any? { |c| check_last_pusher(c) }

        # If neither dismiss_stale_reviews nor last_push_approval are set, reviews are always current so we don't need
        # to compute their statuses.
        if dismiss_stale_reviews || last_push_approval
          # Use the before_oid of the ref update as the "current base branch HEAD". This avoids many potential races,
          # since the ref_update will fail anyway if the base branch moves while policies are evaluating.
          # The exception is when a PR is closed. In this case, use the old base_sha so we do not invalidate reviews with a merge base change
          review_statuses = pull_request.compute_review_statuses(head_sha: pull_request.head_sha,
            base_sha: pull_request.closed? ? pull_request.base_sha : ref_update.before_oid)
        else
          review_statuses = Hash[pull_request.latest_enforced_reviews(writers_only: true).map { |r| [r, :current] }]
        end

        # Stale approvals are a bad experience, because they sit in the review section with a green checkmark, but the
        # user is unable to merge the PR. Previously, if an approval didn't get dismissed for some reason, you could
        # just merge the PR even though you shouldn't be able to. Strict policy won't let you merge with stale approvals.
        # Stale approvals can come from:
        #  - approvals which were submitted before we started promoting approvals
        #  - approvals which became stale with no policy, then a dismissal policy was later added to the target branch
        #  - approvals where the sync job failed at any point before or during dismiss_stale_reviews method or never ran
        if dismiss_stale_reviews_enforce && pull_request.open? && pull_request.head_repository
          stale_approval_count = review_statuses.count { |review, status| review.approved? && status != :current }
          if stale_approval_count > 0
            if repository.feature_enabled?(:disable_rule_engine_pull_request_sync)
              has_unsynced_push = pull_request.latest_unsynced_push_to_head_ref.present?
              GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.dismissing_stale_approvals",
                tags: ["stale_approval_count:#{stale_approval_count}", "resolve_with_sync:false", "has_unsynced_push:#{has_unsynced_push}"])
              PullRequests::UpdateReviewsJob.perform_later(pull_request, actor:)
            else
              # The system can be pretty noisy with calling these rule checks, but synchronize runs on a background job.
              # Without rate limiting, we might queue up the job many times before the first one ran and dismissed stale
              # reviews. Rate limit it to once every few minutes.
              rate_limit_key = "stale_approval_sync_job_rate_limit.#{pull_request.head_repository_id}.#{pull_request.id}"
              rate_limited = GitHub.kv.exists(rate_limit_key).value { false } # rubocop:todo GitHub/DoNotUseGlobalKv

              GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.dismissing_stale_approvals",
                tags: ["stale_approval_count:#{stale_approval_count}", "rate_limited:#{rate_limited}", "resolve_with_sync:true"])

              if !rate_limited
                ActiveRecord::Base.connected_to(role: :writing) do
                  # rubocop:todo GitHub/DoNotUseGlobalKv
                  GitHub.kv.set(rate_limit_key, "true", expires: DISMISS_STALE_APPROVALS_RATE_LIMIT.from_now)
                  # rubocop:enable GitHub/DoNotUseGlobalKv
                end

                # The PR sync job will promote whichever approvals it can, and dismiss any stale approvals.
                SynchronizePullRequestJob.perform_later(
                  pull_request_id: pull_request.id,
                  user: pull_request.user,
                  installation: pull_request.user.try(:installation),
                  repo: pull_request.head_repository,
                  forced: false,
                  ref: nil, before: nil, after: nil,
                  promote_reviews: true,
                )
              end
            end
          end
        end

        # The effects of `dismiss_stale_reviews_on_push` bleed over into other policies.
        #
        # Example: Policy A dismisses reviews & requires 0 approvals. Policy B does not dismiss but requires 2 approvals.
        # Even though policy B doesn't care about staleness, the minimum approver count will need 2 *current* reviews
        # to satisfy policy B. This is because when policy A dismisses an approval, it gets dismissed for all policies
        # not just for policy A.
        #
        # This is important because we need to compute the right decision, even if some sort of race condition or job
        # failure means that some stale reviews aren't dismissed yet. Also there is the case where an update is pushed,
        # and review dismissal is turned on later, after the push happened.
        #
        # Note: If a rule is in evaluate mode, we will not let it ignore non-current reviews for other rules. The exception
        # is if the evaluate mode rule is the only rule we are running.
        #
        # TL,DR: If *any* policy sets `dismiss_stale_reviews_on_push`, *all* policies will ignore stale reviews.
        if dismiss_stale_reviews_enforce
          current_reviews = review_statuses.filter_map { |review, status| review if status == :current }
        else
          current_reviews = review_statuses.keys
        end

        if rule_configs.size > 1
          failed_policy_configs = T.let([], T::Array[RepositoryRuleConfiguration])

          all_policy_decisions = rule_configs.each_with_object({}) do |rule_config, h|
            # Special case: if the rule is in evaluate mode and wants to dismiss stale reviews but dismiss stale reviews is not enforced
            # by another enabled rule, we should allow this rule to consider just current reviews (as if reviews were being dismissed)
            reviews = if !dismiss_stale_reviews_enforce && rule_config.param("dismiss_stale_reviews_on_push") && rule_config.repository_ruleset&.evaluate?
              review_statuses.filter_map { |review, status| review if status == :current }
            else
              current_reviews
            end
            policy_decision = check_reviews(ref_update, pull_request, reviews, review_statuses, rule_config, policy_commit_oid)

            h[rule_config] = policy_decision

            if !policy_decision.rules_fulfilled
              failed_policy_configs << rule_config
            end
          end

          if failed_policy_configs.any?
            # We're attempting to tell the user what is failing, which may not be expressible as a single decision.
            # Do the best we can by combining whichever policies are currently failing.
            restrictive_policy = restrictive_policy_configuration(failed_policy_configs, all_policy_decisions)

            # We seriously need to find a way to do this without calling the entire policy chain a second time. Yuck.
            decision = check_reviews(ref_update, pull_request, current_reviews, review_statuses, restrictive_policy, policy_commit_oid)
          else
            # All policies are passing; generate a passing decision
            decision = summarized_approval_decision(ref_update, current_reviews, rule_configs)
          end

          # Attach all policies to the primary decision
          all_policy_decisions.each do |rule_config, policy_decision|
            decision.add_rule_decision(rule_config, policy_decision)
          end
        else
          rule_config = T.must(rule_configs.first)
          # If the only rule we are running is in evaluate mode and wants to dismiss stale reviews
          # ignore stale reviews for this rule
          if rule_config.param("dismiss_stale_reviews_on_push") && rule_config.repository_ruleset&.evaluate?
            current_reviews = review_statuses.filter_map { |review, status| review if status == :current }
          end
          decision = check_reviews(ref_update, pull_request, current_reviews, review_statuses, rule_config, policy_commit_oid)
          decision.add_rule_decision(rule_config, decision)
        end

        decision.review_statuses.merge!(review_statuses)

        decision
      end
    end

    # Returns the most restrictive set of policy options for the given set of policy configurations
    # This is used to build the primary decision for the UI if we have multiple policies that are in effect
    sig do params(
      failed_policy_configs: T::Array[RepositoryRuleConfiguration],
      all_policy_decisions: T::Hash[RepositoryRuleConfiguration, PullRequestReviewRule::Decision])
      .returns(RepositoryRuleConfiguration)
    end
    def restrictive_policy_configuration(failed_policy_configs, all_policy_decisions)
      # Search through all pull_request rule configurations to find required_reviwers configs. For each owner listed as
      # a required reviewer, pick one of the rules with the highest minimum approvals.
      failing_required_reviewers_all_configs = failed_policy_configs.filter_map do |config|
        decision = T.must(all_policy_decisions[config])

        # Pull all the RequiredReviewerStatus objects out of the instrumentation payloads for all failing decisions
        all_statuses = T.cast(decision.instrumentation_payload[:required_reviewers], T.nilable(T::Array[RequiredReviewerStatus]))
        failing_statuses = all_statuses&.reject(&:is_passing)
        next unless failing_statuses.present?

        all_required_reviewers_this_config = config.param("required_reviewers")

        failing_statuses.map do |failure|
          owner_id = failure.owner_id
          all_required_reviewers_this_config.find { _1["reviewer_id"] == owner_id }
        end
      end.flatten

      # For each failing required reviewer, pick one config from those with highest minimum_approvals
      # (doesn't matter which one since they're all failing)
      strictest_required_reviewers = failing_required_reviewers_all_configs
        .group_by { _1["reviewer_id"] }
        .map do |_reviewer_id, failures|
          failures.max { |a, b| a["minimum_approvals"] <=> b["minimum_approvals"] }
        end

      RepositoryRuleConfiguration.new(
        rule_type: :pull_request,
        parameters: {
          required_approving_review_count: failed_policy_configs.map { |c| c.param("required_approving_review_count") }.max,
          require_code_owner_review: failed_policy_configs.any? { |c| c.param("require_code_owner_review") },
          dismiss_stale_reviews_on_push: failed_policy_configs.any? { |c| c.param("dismiss_stale_reviews_on_push") },
          require_last_push_approval: failed_policy_configs.any? { |c| c.param("require_last_push_approval") },
          required_review_thread_resolution: failed_policy_configs.any? { |c| c.param("required_review_thread_resolution") },
          required_reviewers: strictest_required_reviewers,
        }
      )
    end

    # Private: check one policy for a single pull request
    sig do params(
      ref_update: RuleEngine::Types::NullableRefUpdate,
      pull_request: PullRequest,
      reviews: T::Array[PullRequestReview],
      review_statuses: T::Hash[PullRequestReview, Symbol],
      rule_config: RepositoryRuleConfiguration,
      commit_oid: String)
      .returns(PullRequestReviewRule::Decision)
    end
    def check_reviews(ref_update, pull_request, reviews, review_statuses, rule_config, commit_oid)
      reason = :review_policy_not_satisfied
      rules_fulfilled = false
      summary, message = nil, nil

      payload = default_instrumentation_payload(reviews)
      required_approval_count = rule_config.param("required_approving_review_count")

      evaluate_result = evaluate_required_reviewers(pull_request, reviews, commit_oid, rule_config)
      # We attach these even if review requirements are met, so that it will become part of the suite
      payload[:required_reviewers] = evaluate_result.statuses if evaluate_result.statuses

      begin
        case
        when reviews.any?(&:changes_requested?)
          summary = "Changes requested"
          message = build_message(reviews) + " by reviewers with write access."
          payload[:has_requested_changes] = true

        when evaluate_result.blocking_reason
          summary = "Awaiting required approvals"
          message = evaluate_result.blocking_reason
          payload[:awaiting_required_approvals] = true

        when (waiting_on = code_owners_awaiting_review(pull_request, reviews, commit_oid, rule_config)).any?
          summary = "Code owner review required"
          message = awaiting_code_owners_message(waiting_on)
          payload[:code_owner_review_required] = true

        when soc2_reason = awaiting_soc2_approval_process(pull_request, reviews)
          summary = "Review from compliance team required"
          message = soc2_reason
          payload[:soc2_approval_process_required] = true

        when !thread_resolution_policy_met?(rule_config, pull_request)
          summary = "Conversation resolution required"
          message = "A conversation must be resolved before this pull request can be merged."
          payload[:thread_resolution_required] = true

        when ref_update.is_a?(Git::Branch::Update) && ui_merge_type_blocking?(ref_update, rule_config)
          if ref_update.merge_method == :merge
            summary = "Merge commit not allowed"
          elsif ref_update.merge_method == :squash
            summary = "Squash commit not allowed"
          elsif ref_update.merge_method == :rebase
            summary = "Rebase merge not allowed"
          end
          message = "Merge method '#{ref_update.merge_method}' is not allowed for this base branch."

        when (merge_type_failed_reason = check_cli_merge_type(ref_update, rule_config))
          if merge_type_failed_reason == :merge_commit_blocked
            summary = "Merge commit not allowed"
            message = "Merge commits are not allowed in this repository."
          elsif merge_type_failed_reason == :rebase_and_squash_merge_blocked
            summary = "Rebase and squash merge not allowed"
            message = "When rebase and squash merges are not allowed, a merge commit must be used."
          elsif merge_type_failed_reason == :rebase_blocked_squash_rejected
            merge_commits_allowed = rule_config.param("allowed_merge_types")&.include?("merge")
            summary = "Rebase merge not allowed"
            message = "When rebase merges are not allowed, merges must occur on the web#{merge_commits_allowed ? " or with a merge commit" : ""}."
          end

        when required_approval_count == 0 && !check_last_pusher(rule_config)
          rules_fulfilled = true
          reason = :review_policy_not_required
          summary = "Approval not required"
          message = "This pull request may be merged without approvals."

        when !(last_pusher_policy = last_pusher_policy_info(pull_request, review_statuses, rule_config)).policy_met
          summary = "Review required"
          message = build_last_pusher_message(pull_request, last_pusher_policy, review_statuses, required_approval_count)
          payload[:last_push_approval_required] = true
          payload[:approving_reviews_required] = true

        when ((count = reviews.select(&:approved?).uniq(&:user_id).count) >= required_approval_count)
          rules_fulfilled = true
          reason = :review_approved
          summary = "Changes approved"
          message = build_message(reviews) + " by reviewers with write access."
        else
          summary = "Review required"
          message = build_required_reviews_message(required_approval_count)
          payload[:approving_reviews_required] = true
          payload[:approving_reviews_count] = count
        end
      rescue PullRequest::DetermineCodeownersError
        summary = "Code owner review required"
        message = "Could not determine code owners from the current diff."
        payload[:code_owner_review_required] = true
      end

      PullRequestReviewRule::Decision.new(ref_update, rules_fulfilled,
        reason: {
          code: reason,
          summary: summary,
          message: message,
          instrumentation_payload: payload
        },
        instrumentation_payload: payload
      )
    end

    sig { params(ref_update: Git::Branch::Update, rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def ui_merge_type_blocking?(ref_update, rule_config)
      return false unless repository.feature_enabled_for_source?(:pull_request_rule_merge_types)
      return false unless ref_update.merge_method

      !rule_config.param("allowed_merge_types").include?(ref_update.merge_method.to_s)
    end

    sig { params(ref_update: T.any(Git::Ref::Update, Git::Ref::Update::Null), rule_config: RepositoryRuleConfiguration).returns(T.nilable(Symbol)) }
    def check_cli_merge_type(ref_update, rule_config)
      return unless repository.feature_enabled_for_source?(:pull_request_rule_merge_types) && @cli_merge && ref_update.is_a?(Git::Ref::Update)

      merge_commits_allowed = rule_config.param("allowed_merge_types")&.include?("merge")
      squash_commits_allowed = rule_config.param("allowed_merge_types")&.include?("squash")
      rebase_commits_allowed = rule_config.param("allowed_merge_types")&.include?("rebase")

      is_merge_commit = ref_update.after_commit&.parent_oids&.count > 1
      if !merge_commits_allowed && is_merge_commit
        :merge_commit_blocked
      elsif !rebase_commits_allowed && !is_merge_commit
        behind, ahead = GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.commit_ahead_count") do
          comparison = GitHub::Comparison.deprecated_build(repository, ref_update.refname, ref_update.after_oid)
          comparison.valid? ? comparison.relationship.map(&:to_i) : [0, 0]
        end
        if squash_commits_allowed
          ahead == 1 ? nil : :rebase_blocked_squash_rejected
        else
          :rebase_and_squash_merge_blocked
        end
      end
    end

    sig { params(decision: PullRequestReviewRule::Decision).returns(T::Boolean) }
    def policy_required_and_fulfilled?(decision)
      decision.rules_fulfilled? &&
        decision.reason.code != :review_policy_not_required
    end

    # Private: Returns a Hash of the default data we want for the instrumentation payload for a single Decision.
    # Return type is a plain Hash because you can put anything you want in it.
    sig { params(reviews: T::Enumerable[PullRequestReview]).returns(Hash) }
    def default_instrumentation_payload(reviews)
      { review_ids: reviews.map(&:id) }
    end

    ################################################
    ### Decision Builder Section
    ################################################

    # Returns a Decision for a ref_update where there is not pull request policy
    sig do params(
      ref_update: RuleEngine::Types::NullableRefUpdate,
      reviews: T.nilable(T::Enumerable[PullRequestReview]))
      .returns(PullRequestReviewRule::Decision)
    end
    def decision_approved_no_policies_found(ref_update, reviews)
      summary, message = nil, nil
      reviews ||= []
      payload = default_instrumentation_payload(reviews)

      if reviews.any?(&:changes_requested?)
        summary = "Changes requested"
        message = build_message(reviews)
        payload[:has_requested_changes] = true
      elsif reviews.any?(&:approved?)
        summary = "Changes approved"
        message = build_message(reviews)
      end

      payload[:approving_reviews_count] = reviews.count(&:approved?)

      PullRequestReviewRule::Decision.success(ref_update,
        reason: {
          code: :review_policy_not_required,
          summary: summary,
          message: message,
        },
        instrumentation_payload: payload,
      )
    end

    # Rejecting when user pushes, and we don't find any PR at all
    sig do params(
      ref_update: RuleEngine::Types::NullableRefUpdate,
      rule_configs: T::Array[RepositoryRuleConfiguration])
      .returns(PullRequestReviewRule::Decision)
    end
    def decision_rejected_no_pull_request(ref_update, rule_configs)
      payload = default_instrumentation_payload([])
      payload[:approving_reviews_count] = 0 # No PRs found -> no approvals found

      required_approval_count = rule_configs.map { |cfg| cfg.param("required_approving_review_count") }.max || 0
      last_push_approval_required = rule_configs.any? { |cfg| check_last_pusher(cfg) }
      payload[:approving_reviews_required] = required_approval_count > 0 || last_push_approval_required

      decision = PullRequestReviewRule::Decision.new(
        ref_update, false,
        reason: {
          code: :review_policy_not_satisfied,
          summary: "Pull request required",
          message: "Changes must be made through a pull request.",
          instrumentation_payload: payload
        },
        instrumentation_payload: payload
      )

      # Add a sub-decision for each policy config
      decision_clone = decision.clone
      rule_configs.each { |config| decision.add_rule_decision(config, decision_clone) }

      decision
    end

    # Approval decision which summarizes multiple approved pull request branch protections
    sig do params(
      ref_update: RuleEngine::Types::NullableRefUpdate,
      reviews: T::Enumerable[PullRequestReview],
      rule_configs: T::Array[RepositoryRuleConfiguration])
      .returns(PullRequestReviewRule::Decision)
    end
    def summarized_approval_decision(ref_update, reviews, rule_configs)
      reason = if rule_configs.any? { |c| c.param("required_approving_review_count") > 0 || check_last_pusher(c) }
        {
          code: :review_approved,
          summary: "Changes approved",
          message: build_message(reviews) + " by reviewers with write access.",
        }
      else
        {
          code: :review_policy_not_required,
          summary: "Approval not required",
          message: "This pull request may be merged without approvals.",
        }
      end

      PullRequestReviewRule::Decision.success(ref_update,
        reason: reason,
        instrumentation_payload: default_instrumentation_payload(reviews)
      )
    end

    ################################################
    ### Thread Resolution Section
    ################################################

    sig { params(rule_config: RepositoryRuleConfiguration, pull_request: PullRequest).returns(T::Boolean) }
    def thread_resolution_policy_met?(rule_config, pull_request)
      return true if !rule_config.param("required_review_thread_resolution")

      # Once branch protections are removed, we can move the function into this class
      discussion_policy = Rules::ThreadResolutionRule.new
      discussion_policy.all_pull_request_review_threads_resolved?(pull_request)
    end

    ################################################
    ### Last Pusher Section
    ################################################

    class LastPushPolicyResult

      attr_accessor :policy_met, :last_push_user, :push_not_found, :last_push, :reason

      sig { params(policy_met: T::Boolean, last_push_user: T.nilable(User), push_not_found: T::Boolean, last_push: T.nilable(::Repositories::Push), reason: T.nilable(Reason)).void }
      def initialize(policy_met:, last_push_user: nil, push_not_found: false, last_push: nil, reason: nil)
        @policy_met = policy_met
        @last_push_user = last_push_user
        @push_not_found = push_not_found
        @last_push = last_push
        @reason = reason
      end

      # Result for exemption evaluation
      class Reason < T::Enum
        enums do
          NoCurrentApprovals = new # There are no current approvals. We use this to exit early to avoid the expensive calculation of finding the last pusher
          NoValidApprovals = new # We could not find enough valid approvals to satisfy the policy
          NoPullRequest = new # There is no PR
          PushNotFound = new # Unable to find the push
        end
      end
    end

    # Private: return true if we need to check for who made the last push
    sig { params(rule_config: RepositoryRuleConfiguration).returns(T::Boolean) }
    def check_last_pusher(rule_config)
      rule_config.param("require_last_push_approval")
    end

    # Private: Look up info for last pusher policy.
    #
    # A full result is returned at once to avoid multiple lookups
    # Since multiple people can push up the same commit via different branches, caching isn't an option
    # Returns LastPushPolicyResult
    sig do params(
      pull_request: PullRequest,
      review_statuses: T::Hash[PullRequestReview, Symbol],
      rule_config: RepositoryRuleConfiguration)
      .returns(LastPushPolicyResult)
    end
    def last_pusher_policy_info(pull_request, review_statuses, rule_config)
      # Return as true if we don't need to check for the last pusher
      return LastPushPolicyResult.new(policy_met: true) unless check_last_pusher(rule_config)

      # No pull requests means you can't possibly have any reviews, so we can return here
      return LastPushPolicyResult.new(policy_met: false, reason: LastPushPolicyResult::Reason::NoPullRequest) if pull_request.nil?

      current_approvals = review_statuses.filter_map { |review, status| review if review.approved? && status == :current }

      # skip this to provide a better UX and tell the user who made the last push
      unless repository.async_scoped_feature_flag_enabled?(:find_last_push_without_approvals).sync
        # If none of the reviews are current, there must have been reviewable commits pushed since any approvals
        return LastPushPolicyResult.new(policy_met: false, reason: LastPushPolicyResult::Reason::NoCurrentApprovals) if current_approvals.empty?
      end

      # If multiple people have approved the most recent reviewable commit, at most one of them is the last pusher
      return LastPushPolicyResult.new(policy_met: true) if current_approvals.count > 1

      # If we get here, we know there are either no approvals or exactly one current approval.
      # This is inconvenient, because if we have one approval, the rule might be passing
      # (if the last pusher is not the sole approver) or might be failing (if the last pusher is the sole approver).
      # If there is no approval, we know the rule is failing, but we want to find who made the last push anyway
      # to inform users who is disqualified from approving (due to making the last push)
      sole_approval = current_approvals.first

      last_push = last_reviewable_push(pull_request, sole_approval)

      if last_push.nil?
        GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.last_push_policy.push_not_found", tags: ["strict:true"])
        # We weren't able to find the commit on the Pushes table
        # One known scenario where this could happen is when we don't have a head repo,
        # which can occur because PRs can have foreign keys to repos that may have been deleted.
        # If we can't find the push for any reason, the policy does not pass
        GitHub.logger.info(
          "Unable to find Push record for commit",
          "gh.repo.id": repository.id,
          "gh.pull_request.id": pull_request.id,
          "gh.pull_request.sole_approval.id": (sole_approval&.id || "nil"),
        )
        LastPushPolicyResult.new(policy_met: false, push_not_found: true, reason: LastPushPolicyResult::Reason::PushNotFound)
      elsif sole_approval.nil? || last_push.pusher_id == sole_approval.user_id
        LastPushPolicyResult.new(policy_met: false, last_push_user: User.find_by(id: last_push.pusher_id), last_push: last_push, reason: LastPushPolicyResult::Reason::NoValidApprovals)
      else
        LastPushPolicyResult.new(policy_met: true)
      end
    end

    # Private: Find the most recent push to a branch which has reviewable changes
    sig { params(pull_request: PullRequest, sole_approval: T.nilable(PullRequestReview)).returns(T.nilable(::Repositories::Push)) }
    def last_reviewable_push(pull_request, sole_approval)
      science "last_reviewable_push_new_algo" do |e|
        e.context(
          pull_request_id: pull_request.id,
          pull_request_number: pull_request.number,
          pull_request_open: pull_request.open?,
          pull_request_merged: pull_request.merged?,
          pull_request_merged_at: pull_request.merged_at,
          pull_request_head_sha: pull_request.head_sha,
          pull_request_base_sha: pull_request.base_sha,
          pull_request_merge_commit_sha: pull_request.merge_commit_sha,
          pull_request_best_merge_base_sha: pull_request.find_best_merge_base_sha(use_current_base_sha: true),
          repo_id: repository.try(:id),
          repo_name: repository.try(:name),
          repo_public: repository.try(:public?) || false,
          owner_id: repository.try(:owner).try(:id),
          owner_login: repository.try(:owner).try(:display_login),
          review_id: sole_approval.try(:id),
          review_head: sole_approval.try(:head_sha),
          review_merge_base: sole_approval.try(:merge_base_sha),
        )
        e.use { last_reviewable_push_old(pull_request, sole_approval) }
        e.try { PullRequestStrictReviewRule.last_reviewable_push_new(pull_request, repository, repositories_domain) }
        e.clean do |value|
          {
            id: value.try(:id), pushed_at: value.try(:pushed_at), pusher_id: value.try(:pusher_id),
            before: value.try(:before), after: value.try(:after)
          }
        end
        e.run_if do
          false #temporarily disable the experiment
          # repository.async_scoped_feature_flag_enabled?(:last_reviewable_push_new_algo_experiment).sync ||
          # The `if_public` flag lets us enable the experiment for some % of public repos. It's much easier to
          # investigate any mismatches if we can just look at the repo without asking a customer for permission.
          # (repository.public? && repository.feature_enabled?(:last_reviewable_push_new_algo_experiment_if_public))
        end
      end
    end

    # Private: Find the most recent push to a branch which has reviewable changes
    sig { params(pull_request: PullRequest, sole_approval: T.nilable(PullRequestReview)).returns(T.nilable(::Repositories::Push)) }
    def last_reviewable_push_old(pull_request, sole_approval)
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.last_push_for_commit",
        tags: ["has_sole_approval:#{!!sole_approval}", "strict:true", "algorithm:old"]) do

        batch_size = if (pull_request.repository&.feature_enabled?(:adjust_last_pusher_settings) ||
          pull_request.repository&.owner&.feature_enabled?(:adjust_last_pusher_settings)) &&
          GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i > 0

          GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i
        else
          DEFAULT_LAST_PUSHER_BATCH_SIZE
        end
        timeout = if (pull_request.repository&.feature_enabled?(:adjust_last_pusher_settings) ||
          pull_request.repository&.owner&.feature_enabled?(:adjust_last_pusher_settings)) &&
          GitHub.flipper[:last_pusher_timeout].percentage_of_time_value > 0

          GitHub.flipper[:last_pusher_timeout].percentage_of_time_value
        else
          DEFAULT_LAST_PUSHER_TIMEOUT
        end
        # Uncomment this if you need to debug
        # timeout = 15.minutes if Rails.env.development? || Rails.env.test?

        head_repo_id = pull_request.head_repository&.id
        return nil if head_repo_id.nil? # head repo may have been deleted
        refs = ["refs/heads/#{pull_request.head_ref}"]

        number_of_pushes_diffed = 0
        timer_expired = false
        last_push = T.let(nil, T.nilable(::Repositories::Push))

        records = repositories_domain.pushes.by_repository_id_and_refs(repository_id: head_repo_id, refs: refs, limit: batch_size)
        offset = records.count

        begin
          GitHub::Timer.timeout(timeout) do
            while true
              last_push = records.find do |push|
                # Only interested in pushes that happened before the review was submitted (if there was an approval)
                # We needn't consider pushes which came after, because we know sole_approval status is "current", so
                # there can't be reviewable changes after it was submitted.
                if sole_approval && push.pushed_at > T.unsafe(sole_approval).submitted_at
                  false
                else
                  # It shouldn't really be possible to see a deletion push, because there should be a more-recent creation
                  # push which ends the search, or else the branch wouldn't exist and the PR would be closed.
                  return nil if push.deleted?

                  number_of_pushes_diffed += 1
                  return push if push.created? # a creation is reviewable

                  pull_request.has_reviewable_diffs?(before: push.before, after: push.after)
                end
              end

              break if last_push || records.count < batch_size # We got fewer records than we asked for, so we're done

              records = repositories_domain.pushes.by_repository_id_and_refs(repository_id: head_repo_id, refs: refs, offset: offset, limit: batch_size)
              offset += records.count
            end
          end
        rescue GitHub::Timer::Error
          timer_expired = true
          GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.last_push_for_commit.exceeded_limit",
            tags: ["reason:timer_expired", "strict:true", "algorithm:old"])
          GitHub.logger.info("Timed out while looking for last pusher", {
            "gh.pull_request.id": pull_request.id,
            "gh.pull_request.number": pull_request.number,
            "gh.pull_request.head_repo.id": head_repo_id,
            "gh.pull_request.base_repo.id": pull_request.base_repository_id,
            "gh.repo.last_reviewable_push.timeout": timeout,
            "gh.repo.last_reviewable_push.batch_size": batch_size,
            "gh.repo.last_reviewable_push.pushes_diffed": number_of_pushes_diffed,
            "gh.repo.last_reviewable_push.algorithm": "old",
            })
        end

        GitHub.logger.info("Completed last reviewable push search", {
          "gh.pull_request.id": pull_request.id,
          "gh.pull_request.number": pull_request.number,
          "gh.pull_request.head_repo.id": head_repo_id,
          "gh.pull_request.base_repo.id": pull_request.base_repository_id,
          "gh.repo.last_reviewable_push.found_last_push": !last_push.nil?,
          "gh.repo.last_reviewable_push.timed_out": timer_expired,
          "gh.repo.last_reviewable_push.algorithm": "old",
        })

        # Number of pushes diffed in order to determine if there were any changes
        GitHub.dogstats.distribution(
          "repository_rules_engine.rule.pull_request.last_push_for_commit.num_pushes_diffed", number_of_pushes_diffed,
          tags: ["found_last_push:#{!last_push.nil?}", "strict:true", "algorithm:old", "timer_expired:#{timer_expired}"]
        )

        last_push
      end
    end

    # Find the most recent push to a branch which has reviewable changes, updating the cached last push if necessary
    sig do params(
      pull_request: PullRequest,
      repository: Repository,
      repositories_domain: Repositories::Domain,
      from_push_job: T::Boolean)
      .returns(T.nilable(::Repositories::Push))
    end
    public_class_method def self.last_reviewable_push_new(pull_request, repository, repositories_domain, from_push_job: false)
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.last_push_for_commit",
        tags: ["strict:true", "algorithm:new"]) do

        batch_size = if (pull_request.repository&.feature_enabled?(:adjust_last_pusher_settings) ||
          pull_request.repository&.owner&.feature_enabled?(:adjust_last_pusher_settings)) &&
          GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i > 0

          GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i
        else
          from_push_job ? DEFAULT_LAST_PUSHER_BATCH_SIZE_JOB_AGENT : DEFAULT_LAST_PUSHER_BATCH_SIZE
        end

        timeout = if (pull_request.repository&.feature_enabled?(:adjust_last_pusher_settings) ||
          pull_request.repository&.owner&.feature_enabled?(:adjust_last_pusher_settings)) &&
          GitHub.flipper[:last_pusher_timeout].percentage_of_time_value > 0

          GitHub.flipper[:last_pusher_timeout].percentage_of_time_value
        else
          from_push_job ? DEFAULT_LAST_PUSHER_TIMEOUT_JOB_AGENT : DEFAULT_LAST_PUSHER_TIMEOUT
        end
        # Uncomment this if you need to debug
        # timeout = 15.minutes if Rails.env.development? || Rails.env.test?

        head_repo_id = pull_request.head_repository&.id
        return nil if head_repo_id.nil? # head repo may have been deleted
        refs = ["refs/heads/#{pull_request.head_ref}"]

        number_of_pushes_diffed = 0
        timer_expired = false
        last_reviewable_push = T.let(nil, T.nilable(::Repositories::Push))
        error = T.let(nil, T.nilable(StandardError))

        # Look to see if the existing cached last push is usable
        if pull_request.last_push && pull_request.last_push&.head_sha == pull_request.head_sha
          last_reviewable_push = pull_request.last_push&.push

          # This shouldn't happen because we don't delete push records. last_push&.push already logs this; we don't need to.
          pull_request.delete_last_reviewable_push unless last_reviewable_push
        end

        begin
          unless last_reviewable_push
            GitHub::Timer.timeout(timeout) do
              pushed_before = T.let(nil, T.nilable(T.any(Time, ActiveSupport::TimeWithZone)))

              if GitHub.flipper[:last_reviewable_push_new_algo_filter_merged_at].enabled? && pull_request.merged?
                # Ignore pushes to head branch which came after the PR was merged
                pushed_before = pull_request.merged_at
              end

              records = repositories_domain.pushes.by_repository_id_and_refs(
                repository_id: head_repo_id,
                refs:,
                pushed_before:,
                limit: batch_size)
              return nil if records.empty?
              offset = records.count

              comparison_commit_oid = pull_request.head_sha
              if head_repo_id != repository.id
                repository.fetch_commits_from_network(T.must(pull_request.head_repository), comparison_commit_oid)
              end
              comparison_commit = repository.commits.find(comparison_commit_oid)
              comparison_merge_base_oid = pull_request.find_best_merge_base_sha(use_current_base_sha: true)

              unless comparison_merge_base_oid
                # Unrecoverale state: head and base branch ancestries are disjoint.
                pull_request.delete_last_reviewable_push
                return nil
              end

              # We expect the first push's `after` to be the current head_sha (if no Pushes are missing)
              expected_after_oid = comparison_commit_oid

              while true
                last_reviewable_push = records.find do |push|

                  # It shouldn't be possible to see a deletion push here, because there would be a more-recent creation
                  # push, which is always reviewable. Otherwise the branch wouldn't exist at all and the PR would be closed.
                  if push.deleted? || push.after.nil? || push.after == GitHub::NULL_OID
                    pull_request.delete_last_reviewable_push
                    return nil
                  end

                  # We walk back from the most recent push until we find one which isn't diff-same to the current head_sha. But it's
                  # possible to find gaps in the pushes table. The hydro job which creates Push records has non-deterministic timing,
                  # so we might get here before the Push record has been created. Or the hydro job could fail, etc.
                  #
                  # We will ignore the discrepency if the `after` of the push is diff-same to the current head_sha, because in that
                  # case there are pushes missing but those missing pushes contain no reviewable changes (still not ideal).
                  #
                  # The previous push's `before` was diff-same to the current head (or we would have stopped). If this push's `after`
                  # is not diff-same, then there must be a gap in the pushes table which contains reviewable changes. In that case
                  # the person who pushed the latest changes can't be determined, because there's no Push record to consult.
                  unless push.after == expected_after_oid || is_diffsame(repository, comparison_merge_base_oid, comparison_commit, nil, T.must(push.after))
                    pull_request.delete_last_reviewable_push
                    return nil
                  end

                  # Expect the next (older) push `after` to be this push's `before`
                  expected_after_oid = push.before

                  # Branch creation is always a reviewable push
                  next true if push.created? || push.before.nil? || push.before == GitHub::NULL_OID

                  # We already know what the last reviewable push was from this SHA, so we can stop looking further
                  if pull_request.last_push && pull_request.last_push&.head_sha == push.after
                    if pull_request.last_push&.push
                      break pull_request.last_push&.push
                    else
                      # Push record disappeared. The method has already logged this.
                      pull_request.delete_last_reviewable_push
                    end
                  end

                  number_of_pushes_diffed += 1
                  # If not diff-same, this is the most recent reviewable push
                  !is_diffsame(repository, comparison_merge_base_oid, comparison_commit, nil, T.must(push.before))
                end

                break if last_reviewable_push || records.count < batch_size # We got fewer records than we asked for, so we're done

                # Get the next batch and keep looking
                records = repositories_domain.pushes.by_repository_id_and_refs(
                  repository_id: head_repo_id,
                  refs:,
                  offset:,
                  limit: batch_size)
                offset += records.count
              end
            end
          end
        rescue GitHub::Timer::Error
          timer_expired = true
          GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.last_push_for_commit.exceeded_limit",
            tags: ["reason:timer_expired", "strict:true", "algorithm:new"])
          GitHub.logger.info("Timed out while looking for last pusher", {
            "gh.pull_request.id": pull_request.id,
            "gh.pull_request.number": pull_request.number,
            "gh.pull_request.head_repo.id": head_repo_id,
            "gh.pull_request.base_repo.id": pull_request.base_repository_id,
            "gh.repo.last_reviewable_push.timeout": timeout,
            "gh.repo.last_reviewable_push.batch_size": batch_size,
            "gh.repo.last_reviewable_push.pushes_diffed": number_of_pushes_diffed,
            "gh.repo.last_reviewable_push.algorithm": "new",
            })
        rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId => e
          error = e
          last_reviewable_push = nil
        ensure
          GitHub.logger.info("Completed last reviewable push search", {
            "gh.pull_request.id": pull_request.id,
            "gh.pull_request.number": pull_request.number,
            "gh.pull_request.head_repo.id": head_repo_id,
            "gh.pull_request.base_repo.id": pull_request.base_repository_id,
            "gh.repo.last_reviewable_push.found_last_push": !last_reviewable_push.nil?,
            "gh.repo.last_reviewable_push.push_id": last_reviewable_push.try(:id),
            "gh.repo.last_reviewable_push.timed_out": timer_expired,
            "gh.repo.last_reviewable_push.exception_type": error.try(:class).try(:name),
            "gh.repo.last_reviewable_push.exception_message": error.try(:message),
            "gh.repo.last_reviewable_push.algorithm": "new",
            })

          # Number of pushes diffed in order to determine if there were any changes
          GitHub.dogstats.distribution(
            "repository_rules_engine.rule.pull_request.last_push_for_commit.num_pushes_diffed", number_of_pushes_diffed,
            tags: ["found_last_push:#{!last_reviewable_push.nil?}", "strict:true", "algorithm:new", "timer_expired:#{timer_expired}"]
          )
        end

        if last_reviewable_push && pull_request.head_sha && pull_request.head_sha != GitHub::NULL_OID
          # Upsert the last reviewable push cache record. This is a fast no-op if existing values haven't changed.
          pull_request.update_last_reviewable_push(push_id: last_reviewable_push.id, head_sha: T.must(pull_request.head_sha))
        end

        last_reviewable_push
      end
    end

    ################################################
    ### SOC2 Section
    ################################################

    sig { returns(T::Boolean) }
    def soc2_approval_process_required?
      return false if !!GitHub.enterprise? # This is a `T.nilable(T::Boolean)`, so we need to get a real boolean.
      # Justification: This awful policy is literally hardwired to name_with_owner
      # rubocop:disable GitHub/DoNotAllowNameWithOwner
      RuleEngine::PullRequestReviewRule::SOC2_REPOS.include?(repository.name_with_owner)
      # rubocop:enable GitHub/DoNotAllowNameWithOwner
    end

    # Private: Check if this policy fails due to Soc 2 review policy compliance not being fulfilled.
    #
    # Soc 2 review process requires that an review is requested to a team ending with '-reviewers' and
    # that at least one of those requests has been fulfilled via an approval review.
    #
    # reviews - An Array of PullRequestReviews that are considered for this policy check.
    #
    # Returns a reason String why Soc 2 compliance is not fulfilled or nil if it is fulfilled.
    sig { params(pull_request: PullRequest, reviews: T::Array[PullRequestReview]).returns(T.nilable(String)) }
    def awaiting_soc2_approval_process(pull_request, reviews)
      return unless soc2_approval_process_required?

      requests = soc2_review_requests(pull_request)

      if requests.none?
        "Waiting on review request to and subsequent approval from a compliance team (i.e. '@github/*-reviewers')."
      elsif filter_requests_fulfilled_by(requests, reviews).none?
        compliance_teams = requests.map { |req| req.reviewer.to_s }
        compliance_teams = compliance_teams.uniq.to_sentence \
          two_words_connector: " or ",
          last_word_connector: ", or "
        "Waiting on approval from at least one compliance team: #{compliance_teams}."
      end
    end

    # Private: Finds any review requests for this PR which are requested for review compliance teams.
    # Returns an Array of ReviewRequests.
    sig { params(pull_request: PullRequest).returns(T::Enumerable[ReviewRequest]) }
    def soc2_review_requests(pull_request)
      review_requests = pull_request.review_requests.not_dismissed.includes(:reviewer, :pull_request_reviews)
      filter_soc2_review_requests(review_requests)
    end

    sig { params(review_requests: T::Enumerable[ReviewRequest]).returns(T::Enumerable[ReviewRequest]) }
    def filter_soc2_review_requests(review_requests)
      review_requests.select do |request|
        request.reviewer.is_a?(Team) && request.reviewer.slug =~ RuleEngine::PullRequestReviewRule::SOC2_REVIEWERS_TEAM_PATTERN
      end
    end

    sig { params(requests: T::Enumerable[ReviewRequest], reviews: T::Array[PullRequestReview]).returns(T::Enumerable[ReviewRequest]) }
    def filter_requests_fulfilled_by(requests, reviews)
      requests.select { |request| (request.pull_request_reviews & reviews).any? }
    end

    ################################################
    ### REQUIRED REVIEWERS section
    ################################################

    class RequiredReviewerStatus < T::Struct
      const :owner_id, String
      const :changed_files, T::Set[String]
      const :matching_patterns, T::Set[String]
      const :owner_review_ids, T::Array[Integer]
      const :owner_approval_count, Integer
      const :minimum_approvals, Integer
      const :is_passing, T::Boolean
    end

    class EvaluateRequiredReviewersResult < T::Struct
      const :blocking_reason, T.nilable(String)
      const :statuses, T.nilable(T::Array[RequiredReviewerStatus])
    end

    sig do params(
      pull_request: PullRequest,
      reviews: T::Array[PullRequestReview],
      commit_oid: String,
      rule_config: RepositoryRuleConfiguration)
      .returns(EvaluateRequiredReviewersResult)
    end
    def evaluate_required_reviewers(pull_request, reviews, commit_oid, rule_config)
      ### Find all the required reviewers rules and compute changed file paths

      return EvaluateRequiredReviewersResult.new unless
        repository.async_scoped_feature_flag_enabled?(:rule_pr_required_reviewers_enforce).sync

      required_reviewers = rule_config.param("required_reviewers")
      return EvaluateRequiredReviewersResult.new if required_reviewers.blank? # No policies apply

      changed_paths = async_trusted_changed_paths(pull_request).sync
      return EvaluateRequiredReviewersResult.new(blocking_reason: "Unable to compute changed file paths") if changed_paths.nil?
      return EvaluateRequiredReviewersResult.new if changed_paths.empty? # No files changed

      # We use the globbing logic from Codeowners::Tree to ensure we have fidelity with which files match which rules
      tree = Codeowners::Tree.new
      changed_paths.each { tree.insert(_1) }

      matching_files_by_owner_id = T.let({}, T::Hash[Integer, T::Set[String]])
      matching_patterns_by_owner_id = T.let({}, T::Hash[Integer, T::Set[String]])
      minimum_approvals_by_owner_id = T.let({}, T::Hash[Integer, Integer])

      ### For each rule, find changed files which match the rule, and the number of approvals required

      required_reviewers.each do |requirement|
        owner_id = T.let(requirement["reviewer_id"].to_s, String)
        file_patterns = T.let(requirement["file_patterns"], T::Array[String])

        parsed = begin
          Platform::Helpers::GlobalId::Next.parse(owner_id)
        rescue Platform::Errors::NotFound
        end
        type_name = parsed&.type
        team_id = parsed&.id
        next unless type_name == "Team" && team_id.present?

        minimum_approvals_by_owner_id[team_id] = T.let(requirement["minimum_approvals"], Integer)

        file_patterns.each do |file_pattern|
          matches = tree.match(file_pattern)

          next if matches.blank?

          matching_files_by_owner_id[team_id] ||= Set.new
          matching_files_by_owner_id[team_id]&.merge(matches)

          matching_patterns_by_owner_id[team_id] ||= Set.new
          matching_patterns_by_owner_id[team_id]&.add(file_pattern)
        end
      end

      return EvaluateRequiredReviewersResult.new if matching_files_by_owner_id.empty? # No changed files match any rules

      ### Retrieve all teams which own at least one changed file

      required_team_ids = matching_files_by_owner_id.keys.sort # sorting makes it easier to write "expected" values for tests
      required_teams = Team.where(id: required_team_ids, organization_id: repository.organization_id, privacy: "closed")

      # Check to see if any of the required teams weren't found, or were found but their privacy is set to "secret"
      # If a repo has a rule which requires a team approval, and is later removed from the org where that Team lives,
      # or the team is made secret, it will "fail blocked" because the team can't be found.
      missing_team_count = required_team_ids.size - required_teams.size
      if missing_team_count > 0
        # Some files require the review of teams which are no longer valid -- perhaps deleted? Fail the rule.
        return EvaluateRequiredReviewersResult.new(blocking_reason: <<~MESSAGE.squish)
          Approval is required from #{missing_team_count}
          #{"team".pluralize(missing_team_count)}
          which couldn't be found.
        MESSAGE
      end

      ### For each team, check which existing PR reviews (if any) were left by a member of that team

      # Some teams have a *lot* of members, so let's not fetch their whole membership list into memory. Check team
      # membership async on the SQL side. We don't need to check team membership of all users, just users who have
      # left a review on this PR.
      reviews_by_team = T.let({}, T::Hash[Team, T::Array[PullRequestReview]])
      required_teams.each { reviews_by_team[_1] = [] }

      membership_check_promises =
        reviews.map do |review|
          required_teams.map do |team|
            Platform::Loaders::IsTeamMemberCheck.load(review.user_id, team.id).then do |is_member|
              reviews_by_team[team]&.append(review) if is_member
            end
          end
        end
      .flatten
      Promise.all(membership_check_promises).sync

      ### Calculate the status of each required team -- does it have enough approvals? Build a list of blocking teams.

      blocking_team_messages = T.let([], T::Array[String])

      statuses = required_teams.map do |team|
        changed_files = T.must(matching_files_by_owner_id[T.must(team.id)])
        matching_patterns = T.must(matching_patterns_by_owner_id[T.must(team.id)])
        minimum_approvals = T.must(minimum_approvals_by_owner_id[T.must(team.id)])

        team_reviews = T.must(reviews_by_team[team])
        owner_review_ids = team_reviews.map { T.must(_1.id) }.sort
        owner_approval_count = team_reviews.count(&:approved?)
        is_passing = owner_approval_count >= minimum_approvals

        if !is_passing
          # Add a message to the list of blocking teams
          missing_approvals = minimum_approvals - owner_approval_count

          blocking_team_messages <<
            if owner_approval_count == 0
              if missing_approvals == 1
                # "sql-team"
                team.name_with_display_owner
              else
                # "sql-team (2 approvals needed)" (with no current approvals, we don't use the word "more")
                "#{team.name_with_display_owner} (#{missing_approvals} approvals needed)"
              end
            else
              # "sql-team (1 more approval needed)"
              # "sql-team (3 more approvals needed)"
              "#{team.name_with_display_owner} (#{missing_approvals} more #{"approval".pluralize(missing_approvals)} needed)"
            end
        end

        RequiredReviewerStatus.new(
          owner_id: team.global_relay_id,
          changed_files:,
          matching_patterns:,
          owner_review_ids:,
          owner_approval_count:,
          minimum_approvals:,
          is_passing:,
        )
      end

      ### Return a reason why the PR is blocked (nil if it's not blocked), and the status all teams which own files in this PR

      blocking_reason = if blocking_team_messages.any?
        max_displayed_teams = 10
        overflow = blocking_team_messages.size - max_displayed_teams

        phrase = blocking_team_messages.sort.take(max_displayed_teams)
          .to_sentence(two_words_connector: " and ", last_word_connector: overflow > 0 ? ", " : ", and ") +
          (overflow > 0 ? ", and #{blocking_team_messages.size - max_displayed_teams} other teams" : "")

        "Waiting on required approvals from #{phrase}."
      end

      EvaluateRequiredReviewersResult.new(blocking_reason:, statuses:)
    end

    class RequiredReviewersSummary < T::Struct
      const :team_id, Integer
      const :changed_files, T::Array[String]
      const :matching_patterns, T::Array[String]

      prop :team, T.nilable(Team)
    end

    sig { params(pull_request: PullRequest).returns(T::Array[RequiredReviewersSummary]) }
    public_class_method def self.summarize_required_reviewers(pull_request)
      return [] unless pull_request.repository&.async_scoped_feature_flag_enabled?(:rule_pr_required_reviewers_enforce)&.sync

      policy_decision = pull_request.merge_state.pull_request_review_policy_decision

      all_statuses = policy_decision.rule_decisions.values.filter_map do |decision|
        decision.instrumentation_payload[:required_reviewers]
      end.flatten

      return [] unless all_statuses.present?

      all_statuses_by_owner_id = all_statuses.group_by(&:owner_id)

      result = T.let([], T::Array[RequiredReviewersSummary])

      all_statuses_by_owner_id.each do |owner_id, statuses|
        changed_files = statuses.flat_map { _1.changed_files.to_a }.uniq
        matching_patterns = statuses.flat_map { _1.matching_patterns.to_a }.uniq

        parsed = begin
          Platform::Helpers::GlobalId::Next.parse(owner_id)
        rescue Platform::Errors::NotFound
          nil
        end
        type_name = parsed&.type
        team_id = parsed&.id
        next unless type_name == "Team" && team_id.present?

        result << RequiredReviewersSummary.new(team_id:, changed_files:, matching_patterns:)
      end

      teams = Team.where(id: result.map(&:team_id))

      result.each do |item|
        item.team = teams.find { _1.id == item.team_id }
      end

      result
    end

    sig { params(pull_request: PullRequest).returns(Promise[T.nilable(T::Array[String])]) }
    def async_trusted_changed_paths(pull_request)
      pull_request.async_build_trusted_comparison.then do |trusted_comparison|
        trusted_comparison.async_build_diff.then do |diff|
          diff.deltas.flat_map(&:paths).uniq
        end
      end.catch do |error|
        Failbot.report(error, "gh.pull_request.id": pull_request.id)
        return Promise.resolve(T.cast(nil, T.nilable(T::Array[String])))
      end
    end

    ################################################
    ### CODEOWNERS section
    ################################################

    # Some of the Sorbet sigs in this section are not complete. I'm not clear on what some of the types are, and
    # whether they are always the same.

    sig do params(
      pull_request: PullRequest,
      reviews: T::Array[PullRequestReview],
      commit_oid: String,
      rule_config: RepositoryRuleConfiguration)
      .returns(T::Set[T.untyped])
    end
    def code_owners_awaiting_review(pull_request, reviews, commit_oid, rule_config)
      return Set.new unless rule_config.param("require_code_owner_review")

      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.find_code_owners_awaiting_review", tags: ["strict:true"]) do
        find_code_owners_awaiting_review(pull_request, reviews, commit_oid)
      end
    end

    sig do params(
      pull_request: PullRequest,
      reviews: T::Array[PullRequestReview],
      commit_oid: String)
      .returns(T::Set[T.untyped])
    end
    def find_code_owners_awaiting_review(pull_request, reviews, commit_oid)
      reviewer_ids = reviews.map(&:user_id)
      codeowners = pull_request.codeowners!

      pull_request_author_id = pull_request.user_id

      codeowners.owners_by_rule.each_with_object(Set.new) do |(_rule, owners), awaiting|
        # Don't block if the PR author is a required code owner. They aren't
        # allowed to review their own PR and being the author fulfills the
        # spirit of enforced code owners.
        owners.reject! { |o| o.instance_of?(User) && pull_request_author_id == o.id }

        awaiting.merge(owners) unless code_owner_reviewed?(owners, reviewer_ids)
      end
    end

    sig do params(
      owners: T::Array[T.untyped], # Some type of rule..?
      reviewer_ids: T::Array[Integer]
      )
      .returns(T::Boolean)
    end
    def code_owner_reviewed?(owners, reviewer_ids)
      teams, users = owners.partition { |o| o.is_a?(Team) }
      return true if (reviewer_ids & users.map(&:id)).any?

      team_member_ids = Team.members_of(teams.map(&:id), immediate_only: false).pluck(:id)
      (reviewer_ids & team_member_ids).any?
    end

    sig { params(waiting_on: T::Set[T.untyped]).returns(String) }
    def awaiting_code_owners_message(waiting_on)
      # Only show the first 10 codeowners to prevent truncation of rule message
      overflow = waiting_on.size > 10
      phrase = waiting_on.take(10).map(&:to_s).sort
        .to_sentence(two_words_connector: " and/or ", last_word_connector: overflow ? ", " : ", and/or ") +
        (overflow ? ", and/or #{waiting_on.size - 10} others" : "")

      "Waiting on code owner review from #{phrase}."
    end

    ################################################
    ### Utility Method Section
    ################################################

    sig { params(reviews: T::Enumerable[PullRequestReview]).returns(String) }
    def build_message(reviews)
      messages = []
      rejected_reviews_count = reviews.count(&:changes_requested?)
      approving_reviews_count = reviews.count(&:approved?)

      if rejected_reviews_count > 0
        messages << "#{rejected_reviews_count} #{"review".pluralize(rejected_reviews_count)} requesting changes"
      end

      if approving_reviews_count > 0
        messages << "#{approving_reviews_count} #{"approving review".pluralize(approving_reviews_count)}"
      end

      messages.join(" and ")
    end

    def build_required_reviews_message(required_approval_count)
      <<~MESSAGE.squish
        At least #{required_approval_count}
        #{"approving review".pluralize(required_approval_count)}
        #{"is".pluralize(required_approval_count)}
        required by reviewers with write access.
      MESSAGE
    end

    sig { params(pull_request: PullRequest, last_pusher_policy: LastPushPolicyResult, review_statuses: T::Hash[PullRequestReview, Symbol], required_approval_count: Integer).returns(String) }
    def build_last_pusher_message(pull_request, last_pusher_policy, review_statuses, required_approval_count)
      message = "New changes require approval from someone other than"

      if last_pusher_policy.last_push_user&.display_login
        message += " #{last_pusher_policy.last_push_user.display_login} because they were the last pusher."
      else
        message += " the last pusher."
      end

      current_reviewers = T.let([], T::Array[User])
      stale_reviewers = T.let([], T::Array[User])
      last_pusher_review_status = T.let(nil, T.nilable(Symbol))
      stale_status = Hash.new { |h, k| h[k] = 0 }

      review_statuses.map do |review, status|
        next unless review.user.present?
        # Remove last pusher from valid reviews
        next if last_pusher_policy.last_push_user&.id == T.must(review.user).id
        if review.approved? && status == :current
          current_reviewers << T.must(review.user)
        elsif review.approved?
          stale_reviewers << T.must(review.user)
          stale_status[status] += 1
        end
      end

      stale_message = if stale_reviewers.any?
        change_message = if stale_status[:stale_head_changed] > 0 && stale_status[:stale_merge_changed] == 0
          "most recent code changes."
        elsif stale_status[:stale_merge_changed] > 0 && stale_status[:stale_head_changed] == 0
          "merge base changed."
        else
          "merge base changed and there were new code changes."
        end

        message = "#{stale_reviewers.count == 1 ? "is" : "are"} stale because #{stale_reviewers.count == 1 ? "it was" : "they were"} submitted before the #{change_message}"

        if stale_reviewers.count < 3
          # Need this sort or unit tests will randomly fail
          " #{"Review".pluralize(stale_reviewers.count)} from #{stale_reviewers.map(&:display_login).sort.to_sentence} #{message}"
        else
          " #{stale_reviewers.count} #{"review".pluralize(stale_reviewers.count)} #{message}"
        end
      end

      if last_pusher_policy.last_push || last_pusher_policy.reason == LastPushPolicyResult::Reason::NoCurrentApprovals
        last_pusher_identifier = if last_pusher_policy.last_push_user&.display_login
          "#{last_pusher_policy.last_push_user.display_login} because they were the last pusher"
        else
          # this happens if we have 0 approvals and don't want to calculate the last pusher
          # see `find_last_push_without_approvals` feature flag
          "the last pusher"
        end

        # If there are no stale reviews, use the original message from above
        if stale_message
          # Overrides original message set above
          message = "Waiting on 1 reapproval from someone other than #{last_pusher_identifier}.#{stale_message}"
        end
      elsif required_approval_count > 1
        # If we are here, this means
        # - couldn't find the last push
        # - we have 1 current approval (more than 1 approval should have passed the policy)
        # - we require more than 1 review
        #
        # Since we need at least 2 current approvals to guarantee 1 of the approvals isn't from the last pusher,
        # we can use the required reviews message instead and not reveal that we couldn't find the last pusher.
        last_pusher_log(
          "Push not found during last pusher evaluation. Defer to required approval count.",
          pull_request,
          "gh.pull_request.required_approval_count": required_approval_count,
        )
        message = build_required_reviews_message(required_approval_count)
        message += stale_message if stale_message
      else
        # If we are here, this means
        # - couldn't find the last push
        # - we have 1 current approval (more than 1 approval should have passed the policy)
        # - we require 0 or 1 reviews
        #
        # We need at least 2 reviews to guarantee the last pusher isn't the only approver
        # We should tell the user why we now require 2 reviews

        required_reviews = 2
        remaining_required_reviews = required_reviews - current_reviewers.count
        message = "Waiting on #{remaining_required_reviews}"

        if remaining_required_reviews == 1
          message += " more approval"
        elsif remaining_required_reviews == 2
          message += (stale_reviewers.any? ? " reapprovals" : " approvals")
        else
          # If not 1 or 2, then something is wrong
          # If they get another approval, that should hopefully get them out of the sticky situation
          GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.last_push_for_commit.unexpected_number_of_reviews", tags: ["strict:true", "new_messaging:true"])
          GitHub.logger.info(
            "Unexpected number of remaining required reviews for last pusher rule",
            "gh.repo.id": repository.id,
            "gh.pull_request.id": pull_request.id,
            "gh.pull_request.number": pull_request.number,
            "gh.pull_request_review.count": review_statuses.keys.count,
            "gh.pull_request_review.ids": review_statuses.keys.map(&:id),
          )
          message = "Requires at least 1 more approval"
        end

        message += " from #{remaining_required_reviews == 1 ? "a reviewer" : "reviewers"} with write access because the last pusher could not be determined."

        if stale_message
          message += stale_message
        end
      end

      message
    end

    sig { params(message: T.nilable(String), pull_request: PullRequest, additional_info: T.nilable(T::Hash[String, T.untyped])).void }
    def last_pusher_log(message, pull_request, additional_info = {})
      hash = {
        "gh.repo.id": repository.id,
        "gh.pull_request.id": pull_request.id,
        "gh.pull_request.number": pull_request.number,
      }.merge(additional_info || {})
      GitHub.logger.info(
        message,
        **hash
      )
    end

    sig do
      params(
        repository: Repository,
        new_merge_base_oid: String,
        new_head_commit: Commit,
        old_merge_base_oid: T.nilable(String),
        old_head_oid: String)
        .returns(T::Boolean)
    end
    private_class_method def self.is_diffsame(repository, new_merge_base_oid, new_head_commit, old_merge_base_oid, old_head_oid)
      begin
        # Changesets are always diffsame to themselves
        return true if (!old_merge_base_oid || new_merge_base_oid == old_merge_base_oid) && new_head_commit.oid == old_head_oid

        return false if old_merge_base_oid && repository.rpc.best_merge_base(new_merge_base_oid, old_head_oid) != old_merge_base_oid

        trusted_merge_commit = repository.commits.create_merge_commit(
          User.ghost,
          new_merge_base_oid,
          old_head_oid
        ).first
        return false unless trusted_merge_commit

        new_head_commit.tree_oid == trusted_merge_commit.tree_oid
      rescue GitRPC::Timeout, GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId
        false
      end
    end

    # Private: Find all pull requests which could possibly allow this ref_update to be approved.
    # This is used when a user pushes a merge to a protected branch, and we're looking to see which
    # pull requests would potentially allow this push to be approved.
    sig { params(ref_update: Git::Ref::Update, verify_pushed_tree: T::Boolean).returns(T::Array[PullRequest]) }
    def candidate_pull_requests_for_push(ref_update, verify_pushed_tree)
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.candidate_pull_requests_for_push", tags: ["strict:true"]) do
        candidate_prs = []
        policy_commit_oids = policy_commit_oids_for_push(ref_update)

        if policy_commit_oids.any?
          candidate_prs.concat(
            repository
            .pull_requests
            .includes(:reviews)
            .open_pulls
            .where(
              head_sha: policy_commit_oids,
              base_ref: ref_update.refname.delete_prefix("refs/heads/"),
              work_in_progress: false)
            .to_a
          )
        end

        # Check pull requests in the same order returned by policy_commit_oids_for_push.
        candidate_prs.sort_by! { |pr| policy_commit_oids.index(pr.head_sha) }

        if verify_pushed_tree && candidate_prs.any?
          # If either dismiss_stale_reviews or require_last_push_approval is set, use strict comparison for the merge.
          # Reject a proposed merge commit unless it's tree-equal with the server-created merge commit.
          candidate_prs.filter! do |pull_request|
            merge_commit_sha =
              if pull_request.merge_commit_up_to_date?
                pull_request.merge_commit_sha
              else
                # this can be called from read-only contexts so we need to manaually specify the writing role
                ActiveRecord::Base.connected_to(role: :writing) { pull_request.create_merge_commit }
              end
            next false if !merge_commit_sha

            merge_commit = repository.commits.find(merge_commit_sha)
            next false if !merge_commit

            ref_update.after_commit&.tree_oid == merge_commit.tree_oid
          end
        end

        GitHub.dogstats.distribution("repository_rules_engine.rule.pull_request.candidate_pull_requests_for_push.result", candidate_prs.count, tags: ["strict:true"])

        candidate_prs
      end
    end

    # Private: Is this proposed commit a 2-parent merge where one parent is the current HEAD of the branch being updated?
    # If so, we will look for pull requests which have the other parent as their head_sha.
    sig { params(ref_update: Git::Ref::Update).returns(T::Array[String]) }
    def policy_commit_oids_for_push(ref_update)
      result = []

      # Not all ref_updates have fast-forward pre-computed
      if ref_update.fast_forward.nil?
        ref_update.fast_forward = repository.rpc.descendant_of?(ref_update.after_oid, ref_update.before_oid)
      end

      # We won't count something as a "candidate" PR if it would require a force push. Code reviews are completely
      # meaningless if the PR is allowed to remove arbitrary commits from branch history.
      if ref_update.fast_forward
        # Perhaps the target branch hasn't moved and the push is a FF of target branch to the PR's current HEAD commit.
        result.push(ref_update.after_oid)

        # Or perhaps this is a 2-parent merge between the target branch's HEAD and the pull request's HEAD.
        if ref_update.after_commit&.parent_oids&.count == 2 &&
          ref_update.after_commit.parent_oids.include?(ref_update.before_oid)

          result.push(ref_update.after_commit.parent_oids.reject { |oid| oid == ref_update.before_oid }.first)
        end
      end

      result
    end

    # Private: Find relevant RepositoryRuleConfigurations for a ref_update
    sig { params(ref_update: RuleEngine::Types::NullableRefUpdate).returns(T::Array[RepositoryRuleConfiguration]) }
    def find_pull_request_policies(ref_update)
      (repository.supports_protected_branches? && policies_by_refname[ref_update.refname]) || []
    end
  end
end
