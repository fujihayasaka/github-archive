# typed: true
# frozen_string_literal: true

module RuleEngine
  class PullRequestReviewRule
    SOC2_REPOS = %w(github/github).freeze
    SOC2_REVIEWERS_TEAM_PATTERN = /-reviewers\z/.freeze
    MERGE_COMMIT_TIMEOUT_SECONDS = 3
    DEFAULT_LAST_PUSHER_BATCH_SIZE = 4
    DEFAULT_LAST_PUSHER_TIMEOUT = 5 # seconds

    include Repositories::Domain::Provider

    # Public: Check the pull request review policy for one or more ref updates
    # for protected branches
    #
    # repository                  - The Repository, Gist, or Unsullied::Wiki whose refs
    #                               are being updated
    # ref_updates                 - Array of Git::Ref::Updates
    # policy_evaluator_by_refname - Hash with qualified ref names as keys and relevant `BranchRuleEvaluator`s as values
    #                               (Passed for performance reasons to avoid duplicate lookups)
    # actor                       - The User attempting to make an update
    #
    # Returns a list of Decisions
    # This method is only called by tests
    def self.check(repository, ref_updates, policy_evaluator_by_refname, actor:)
      policies_by_refname = policy_evaluator_by_refname.map do |refname, policy_evaluator|
        [refname, [policy_evaluator&.pull_request_policy]]
      end.to_h
      check_policies(repository, ref_updates, policies_by_refname, actor: actor)
    end

    # Public: Check the pull request review policy for one or more ref updates
    # for pull request policies
    #
    # repository                       - The Repository, Gist, or Unsullied::Wiki whose refs
    #                                    are being updated
    # policies_by_refname              - Hash with Git::Ref::Updates as keys and an array of relevant `RepositoryRuleConfiguration`s as values
    # actor                            - The User attempting to make an update
    # server_merge                    - Is this a server generated branch merge?
    #
    # Returns a list of Decisions
    def self.check_policies(repository, ref_updates, policies_by_refname, actor:, server_merge: false, cli_merge: false)
      if use_strict_review_policy_class?(repository, policies_by_refname, nil)
        PullRequestStrictReviewRule.new(repository, ref_updates, policies_by_refname, actor:, server_merge:, cli_merge:).check
      else
        new(repository, ref_updates, policies_by_refname, actor:, server_merge:, cli_merge:).check
      end
    end

    # Public: Check the pull request review policy for a single Pull Request.
    #
    # pull_request: PullRequest to check the policy for
    # actor: the User attempting to make an update
    #
    # Returns a single Decision.
    # This does not appear to be used anywhere
    def self.check_pull_request(pull_request:, actor:, ref_update:, policy_evaluator: nil)
      self.async_check_pull_request(pull_request: pull_request, actor: actor, ref_update: ref_update, policy_evaluator: policy_evaluator).sync
    end

    # Public: Check the pull request review policy for a single Pull Request.
    #
    # pull_request: PullRequest to check the policy for
    # actor: the User attempting to make an update
    #
    # Returns a promise resolving to a single Decision.
    def self.async_check_pull_request(pull_request:, actor:, ref_update:, policy_evaluator: nil)
      policy_evaluator ||= pull_request.base_branch_rule_evaluator
      pr_policies = policy_evaluator.try(:pull_request_policies) || [policy_evaluator&.pull_request_policy]

      if use_strict_review_policy_class?(pull_request.repository, { ref_update.refname => pr_policies }, pull_request)
        PullRequestStrictReviewRule.new(pull_request.repository, [ref_update], { ref_update.refname => pr_policies },
          actor: actor, pull_request: pull_request).async_check_pull_request
      else
        new(pull_request.repository, [ref_update], { ref_update.refname => pr_policies }, actor: actor, pull_request: pull_request).
          async_check_pull_request
      end
    end

    # Checks to see if the strict review policy should be used
    def self.use_strict_review_policy_class?(repository, policies_by_refname, pull_request)
      rule_configs = policies_by_refname.values.flatten.compact

      # Strict review class doesn't process this policy option since it combines multiple PRs in one policy decision
      use_strict = rule_configs.none? { |cfg| cfg.param("ignore_approvals_from_contributors") }

      if !use_strict
        GitHub.logger.info("pull_request.ignore_approvals_from_contributors", {
          "git.refs" => policies_by_refname&.keys&.join(","),
          "gh.pull_request.id" => pull_request.try(:id) || "nil",
          "gh.pull_request.number" => pull_request.try(:number) || "nil",
          "gh.repo.id" => repository.try(:id),
          "gh.repo.owner.id" => repository.try(:owner).try(:id),
          "gh.business.id" => repository.try(:owner).try(:business).try(:id),
        })
      end

      use_strict
    end

    def initialize(repository, ref_updates, policies_by_refname, actor:, pull_request: nil, server_merge: false, cli_merge: false)
      @repository = repository
      @ref_updates = ref_updates
      @policies_by_refname = policies_by_refname
      @actor = actor
      @pull_request = pull_request
      @server_merge = server_merge
      @cli_merge = cli_merge
    end

    # Check the policy for a single Pull Request, and return a Decision.
    #
    # For looking up reviews, all pull requests are considered (open and closed ones).
    #
    # Returns a single Decision
    # This does not appear to be used anywhere
    def check_pull_request
      async_check_pull_request.sync
    end

    # Check the policy for a single Pull Request, and return a Decision.
    #
    # For looking up reviews, all pull requests are considered (open and closed ones).
    #
    # Returns a promise resolving to a single Decision
    def async_check_pull_request
      ref_update = ref_updates.first
      commit_oid = pull_request.head_sha
      consider_open_pulls_only = pull_request.open?
      fetch_reviews_promise = Platform::Loaders::PullRequestCheckReviews.load(repository, pull_request, ref_update, consider_open_pulls_only)

      # The non-async code has a call here for:
      # if pull_request
      #       pull_request.latest_enforced_reviews(writers_only: true).each do |review|
      #             reviews << review unless reviews.include?(review)
      #       end
      # end
      # Since the loader code always has a pull request context and it groups by pull_request_id it seems that this part is redundant
      fetch_reviews_promise.then { |reviews| process_policies(ref_update, reviews, commit_oid, consider_open_pulls_only) }
    end

    # Check the review Policy for all the ref updates.
    #
    # For looking up reviews, only open pull requests are considered.
    #
    # Returns an Array of Decision records
    def check
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.check", tags: ["strict:false"]) do
        ref_updates.map do |ref_update|
          rule_commit = policy_commit_for(ref_update)
          decision = check_commit(ref_update, commit_oid: rule_commit.oid)
          if policy_required_and_fulfilled?(decision)
            decision
          elsif relevant_merge_commit?(ref_update, rule_commit)
            if GitHub.flipper[:audit_nonserver_merges].enabled?(repository&.owner)
              merge_result = decision_for_merge_commit(ref_update, rule_commit)

              if merge_result.rules_fulfilled? && !@server_merge
                head_commits = rule_commit.parent_oids - [ref_update.before_oid]

                if rule_commit.parent_oids.length == 2 && head_commits.length == 1
                  begin
                    author_name, author_email = User.git_author_info(User.ghost)
                    message = "Merge #{head_commits.first} into #{ref_update.refname}"

                    merge_oid, error, details = repository.rpc.with_timeout(MERGE_COMMIT_TIMEOUT_SECONDS) do
                      repository.create_merge_commit(ref_update.refname, head_commits.first, { name: author_name, email: author_email, time: Time.now }, message,
                                                         check_tree_with_diff: GitHub.flipper[:create_merge_commit_check_tree_with_diff].enabled?(repository))
                    end

                    if error
                      details = error
                    else
                      merge_commit = repository.commits.find(merge_oid)

                      if merge_commit.tree_oid == rule_commit.tree_oid
                        details = "Clean merge"
                      else
                        details = "Changes added to merge"
                      end
                    end
                  rescue GitRPC::Timeout
                    details = "Merge commit timed out"
                  rescue GitRPC::ObjectMissing, GitRPC::InvalidObject, RepositoryObjectsCollection::InvalidObjectId
                    # this should never happen, but lets prevent exceptions in the unlikely case it does
                    details = "Failed to find merge commit"
                  rescue => e # rubocop:todo Lint/GenericRescue
                    details = e.message
                  end
                else
                  details = "Parent count is #{rule_commit.parent_oids.length}"
                end

                GitHub.logger.info("Untrusted Merge", {
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.repo.id": repository.id,
                  "gh.repo.owner.id": repository.owner&.id,
                  "git.commit.oid": rule_commit.oid,
                  "gh.branch_protection_rule.rule.details": details,
                  "gh.branch_protection_rule.rule.ref": ref_update&.refname,
                })
              end

              merge_result
            else
              decision_for_merge_commit(ref_update, rule_commit)
            end
          else
            decision
          end
        end
      end
    end

    private

    attr_reader :repository, :ref_updates, :policies_by_refname, :actor, :pull_request

    def decision_for_merge_commit(ref_update, rule_commit)
      relevant_parents = rule_commit.parent_oids - [ref_update.before_oid]
      parent_decisions = relevant_parents.map do |parent_oid|
        check_commit(ref_update, commit_oid: parent_oid)
      end

      # TODO create a combined Decision
      if parent_decisions.all?(&:rules_fulfilled?)
        parent_decisions.first
      else
        parent_decisions.find { |decision| !decision.rules_fulfilled? }
      end
    end

    def check_commit(ref_update, commit_oid:, consider_open_pulls_only: true)
      reviews = reviews_for(commit_oid, ref_update, consider_open_pulls_only)

      # Because of a potential race-condition related to updating the PRs `head_sha`
      # in the database from a post receive job, we need to make sure that we include
      # the reviews of the PR at hand.
      if pull_request
        pull_request.latest_enforced_reviews(writers_only: true).each do |review|
          reviews << review unless reviews.include?(review)
        end
      end

      process_policies(ref_update, reviews, commit_oid, consider_open_pulls_only)
    end

    def reviews_for(commit_oid, ref_update, consider_open_pulls_only)
      PullRequestReview::EnforcedLoader.new(
        repository: repository,
        pull_request_head_sha: commit_oid,
        pull_request: pull_request,
        open_pulls_only: consider_open_pulls_only,
        writers_only: true,
        exclude_drafts: true,
        base_ref_name: ref_update.refname
      ).execute
    end

    # Raise when multiple pull requests on the same commit from different head repos are found
    class MultiplePullRequestsFoundError < StandardError; end

    # User ids that have contributed by opening a pull request
    # associated with this commit oid or pushing to its branch
    def contributing_user_ids(commit_oid, consider_open_pulls_only, reviews)
      (
        pull_author_ids(commit_oid, consider_open_pulls_only) |
        pull_pusher_ids(commit_oid, consider_open_pulls_only, reviews)
      )
    end

    # The ids of any Users that pushed (after open) to PRs containing this
    # commit oid.  These users' reviews should not count for approval purposes
    # if the protected branch configuration option
    # `ignore_approvals_from_contributors?` is enabled.
    def pull_pusher_ids(commit_oid, consider_open_pulls_only, reviews)
      @pull_pusher_ids ||= {}
      args = [commit_oid, consider_open_pulls_only]
      return @pull_pusher_ids[args] if @pull_pusher_ids.key?(args)

      # If we don't have a pull request object nor reviews, then we can't determine the head repo
      # and therefore cannot determine the pusher ids
      # It's possible for a pr to refer to a null repo (e.g. deleted repo)
      # remove nulls from the list
      head_repos = head_repositories(reviews).compact
      return @pull_pusher_ids[args] = [] if head_repos.empty?
      raise MultiplePullRequestsFoundError if head_repos.count > 1
      head_repo = head_repos.first

      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.determine_pushers") do
        branches_with_commit_at_head = head_repo.heads.select { |h| h.target_oid == commit_oid }.map(&:name)

        pr_scope = head_repo.pull_requests.where(head_ref: branches_with_commit_at_head)
        pr_scope = pr_scope.open_pulls if consider_open_pulls_only

        # [head_ref, pr_opened_at] for each branch involved in matched PRs
        pr_refs_with_open_timestamps = pr_scope.group_by { |pr| pr.head_ref }
          .collect { |head_ref, prs| [head_ref, prs.min_by { |pr| pr.created_at }.created_at] }

        # Track this value during release to ensure the loop count is low
        GitHub.dogstats.distribution(
          "repository_rules_engine.rule.pull_request.pusher_query_loop_count",
          pr_refs_with_open_timestamps.size
        )

        @pull_pusher_ids[args] = pr_refs_with_open_timestamps.inject([]) do |memo, (head_ref, pr_opened_at)|
          memo |= repositories_domain.pushes.pusher_ids_for_ref(repository: head_repo, ref: head_ref, pushed_at: pr_opened_at)
        end
      end
    end

    def last_push_for_commit(commit_oid, consider_open_pulls_only, head_repo, reviews)
      return nil if head_repo.nil?
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.last_push_for_commit", tags: ["last_reviewable_commit:#{last_reviewable_commit_enabled?}"]) do
        branches_with_commit_at_head = head_repo.heads.select { |h| h.target_oid == commit_oid }.map(&:name)
        pr_scope = repository.pull_requests.where(head_ref: branches_with_commit_at_head)
        pr_scope = pr_scope.open_pulls if consider_open_pulls_only
        pr_refs = pr_scope.pluck(:head_ref).uniq.map { |ref_name| "refs/heads/#{ref_name}" }

        # Track this value during release to ensure the loop count is low
        GitHub.dogstats.distribution(
          "repository_rules_engine.rule.pull_request.last_push_for_commit.ref_size",
          pr_refs.size
        )
        if last_reviewable_commit_enabled?
          # If we don't know the pull request and don't have any reviews, we shouldn't get to this line
          pull = pull_request || reviews.first.pull_request
          return nil if pull.nil?
          batch_size = GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i > 0 ? GitHub.flipper[:last_pusher_batch_size].percentage_of_time_value.to_i : DEFAULT_LAST_PUSHER_BATCH_SIZE
          timeout = GitHub.flipper[:last_pusher_timeout].percentage_of_time_value > 0 ? GitHub.flipper[:last_pusher_timeout].percentage_of_time_value : DEFAULT_LAST_PUSHER_TIMEOUT
          # track number of pushed that were diffed
          # to evaluate how many pushes it took to find the last reviewable push
          number_of_pushes_diffed = 0
          last_reviewable_push = T.let(nil, T.nilable(::Repositories::IPush))
          # We can't limit the query to pushes after the most recent approval
          # because we need to know who made the last reviewable push (i.e. a push that did not introduce changes)
          # in order to verify the approver is not the person who made the push
          records = repositories_domain.pushes.by_repository_id_and_refs(repository_id: head_repo.id, refs: pr_refs, limit: batch_size)

          first_push = records.first
          begin
            GitHub::Timer.timeout(timeout) do
              while last_reviewable_push.nil? && records.any?
                last_reviewable_push = records.find do |push|
                  number_of_pushes_diffed += 1
                  pull.has_reviewable_diffs?(before: push.before, after: push.after)
                end
                records = repositories_domain.pushes.by_repository_id_and_refs(repository_id: head_repo.id, refs: pr_refs, offset: number_of_pushes_diffed, limit: batch_size) if last_reviewable_push.nil?
              end
            end
          rescue GitHub::Timer::Error
            GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.last_push_for_commit.exceeded_limit",
              tags: ["reason:timer_expired", "strict:false"])
          end

          # Number of pushes diffed in order to determine if there were any changes
          GitHub.dogstats.distribution(
            "repository_rules_engine.rule.pull_request.last_push_for_commit.num_pushes_diffed",
            number_of_pushes_diffed, tags: ["found_last_push:#{!last_reviewable_push.nil?}", "strict:false"]
          )

          return last_reviewable_push || first_push
        else
          # Determine who pushed the last head commit
          repositories_domain.pushes.latest_by_after_and_ref(repository_id:  head_repo.id, after: commit_oid, ref: pr_refs)
        end
      end
    end

    # The user_ids that authored any pull request whose head_sha is
    # currently pointing at this commit oid.
    def pull_author_ids(commit_oid, consider_open_pulls_only)
      @pull_author_ids ||= {}
      args = [commit_oid, consider_open_pulls_only]
      return @pull_author_ids[args] if @pull_author_ids.key?(args)
      # TODO update to use the branches_with_commit_at_head approach
      # used in pull_pusher_ids rather than querying on head_sha which
      # is subject to races.
      pr_scope = repository.pull_requests.where(head_sha: commit_oid)
      pr_scope = pr_scope.open_pulls if consider_open_pulls_only
      @pull_author_ids[args] = pr_scope.distinct.pluck(:user_id)
    end

    def process_policies(ref_update, reviews, commit_oid, consider_open_pulls_only)
      rule_configs = find_pull_request_policies(ref_update)

      GitHub.dogstats.distribution("repository_rules_engine.rule.pull_request.process_policies.rule_configs",
        rule_configs&.count || 0, tags: ["strict:false"])
      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.process_policies", tags: ["strict:false"]) do
        if rule_configs&.any?
          if rule_configs.size > 1
            failed_policy_configs = []

            all_policy_decisions = rule_configs.each_with_object({}) do |rule_config, h|
              policy_decision = check_reviews(ref_update, reviews, rule_config, commit_oid, consider_open_pulls_only)
              h[rule_config] = policy_decision

              if !policy_decision.rules_fulfilled
                failed_policy_configs << rule_config
              end
            end

            if failed_policy_configs.any?
              # We're attempting to tell the user what is failing, which may not be expressible as a single decision.
              # Do the best we can by combining whichever policies are currently failing.
              restrictive_policy = restrictive_policy_configuration(failed_policy_configs)
              decision = check_reviews(ref_update, reviews, restrictive_policy, commit_oid, consider_open_pulls_only)
            else
              # All policies are passing; generate a passing decision
              decision = summarized_approval_decision(ref_update, reviews, rule_configs)
            end

            # Attach all policies to the primary decision
            all_policy_decisions.each do |rule_config, policy_decision|
              decision.add_rule_decision(rule_config, policy_decision)
            end
          else
            decision = check_reviews(ref_update, reviews, rule_configs.first, commit_oid, consider_open_pulls_only)
            decision.add_rule_decision(rule_configs.first, decision)
          end

          if pull_request.nil? && GitHub.flipper[:approval_aggregation_telemetry].enabled?(repository.owner) &&
            !rule_configs.any? { |cfg| cfg.param("ignore_approvals_from_contributors") } &&
            rule_configs.any? { |cfg| cfg.param("required_approving_review_count") > 0 } &&
            decision.rules_fulfilled?

            # This is a merge attempt (via PR merge button, API, or CLI push). It required at least one approval, and it
            # has passed all review policies. That doesn't mean it merged successfuly -- other policies may have blocked it.
            log_aggregation_telemetry(ref_update, reviews, rule_configs, commit_oid)
          end

          decision
        else
          check_reviews_non_protected_branch(ref_update, reviews)
        end
      end
    end

    def log_aggregation_telemetry(ref_update, reviews, rule_configs, commit_oid)
      #       This is a sneaky way to find out which PR the user clicked "merge" on if they merged a specific PR
      # vvvv  rather than just pushing to a protected branch. This should work even if the merged PR had no reviews.
      user_merged_pr = nil
      orig_policy_commit = ref_update.try(:rule_commit)

      if orig_policy_commit
        # Find branches with the commit_oid at the head
        branches_with_commit_at_head = repository.heads.select { |h| h.target_oid == commit_oid }.map(&:name)

        # Now find a PR from any of those branches to the target branch which has orig_policy_commit as its merge commit
        unless branches_with_commit_at_head.empty?
          user_merged_pr = repository.pull_requests.open_pulls.
            where(
              head_ref: branches_with_commit_at_head,
              merge_commit_sha: orig_policy_commit.oid,
              base_ref: ref_update.refname.delete_prefix("refs/heads/"))
            .first
        end
      end

      user_merged_pr_id = user_merged_pr&.id
      user_merged_pr_number = user_merged_pr&.number
      # ^^^^  End sneaky way

      # The approval count used by current policy behavior, where we aggregate all PRs
      total_approval_count = reviews.select(&:approved?).uniq(&:user_id).count

      approval_count_by_pr = reviews.select(&:approved?).group_by(&:pull_request_id).transform_values(&:count)
      approval_count_by_pr.default = 0

      max_single_pr_approval_count = approval_count_by_pr.values.max || 0
      max_policy_required_approvers = rule_configs.map { |cfg| cfg.param("required_approving_review_count") }.max

      aggregation_status =
        if user_merged_pr_id
          case
          when approval_count_by_pr[user_merged_pr_id] >= max_policy_required_approvers
            # User merged a PR which had enough approvals all by itself
            :merged_directly
          when max_single_pr_approval_count >= max_policy_required_approvers
            # There was a single PR with enough approvals, but user merged a different PR
            :merged_sibling_pr
          when total_approval_count >= max_policy_required_approvers
            # No single PR had sufficient approvals to merge
            :merged_aggregated_approvals
          else
            # There weren't enough approvals to merge. May as well log it while we're here.
            :merged_invalid
          end
        else
          case
          when max_single_pr_approval_count >= max_policy_required_approvers
            # There was a single PR with enough approvals
            :pushed_single_pr_approval
          when total_approval_count >= max_policy_required_approvers
            # No single PR had sufficient approvals to merge
            :pushed_aggregated_approvals
          else
            # There weren't enough approvals to merge. May as well log it while we're here.
            :pushed_invalid
          end
        end

      GitHub.dogstats.increment(
        "repository_rules_engine.rule.pull_request.approval_aggregation",
        tags: ["aggregation_status:#{aggregation_status}"])

      if aggregation_status != :merged_directly && aggregation_status != :pushed_single_pr_approval
        GitHub.logger.info("PR approved via aggregated approvals", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository.id,
          "gh.repo.owner.id": repository.owner_id,
          "git.commit.oid": commit_oid,
          "gh.pull_request.id": user_merged_pr_id,
          "gh.pull_request.number": user_merged_pr_number,
          "gh.branch_protection_rule.rule.aggregation_status": aggregation_status,
          "gh.branch_protection_rule.rule.user_merged_pr_approvals": approval_count_by_pr[user_merged_pr_id],
          "gh.branch_protection_rule.rule.approved_pr_ids": approval_count_by_pr.keys,
          "gh.branch_protection_rule.rule.total_approvals": total_approval_count,
          "gh.branch_protection_rule.rule.max_single_pr_approvals": max_single_pr_approval_count,
          "gh.branch_protection_rule.rule.required_approvals": max_policy_required_approvers
        })
      end
    end

    # Returns the most restrictive set of policy options for the given set of policy configurations
    # This is used to build the primary decision for the UI if we have multiple policies that are in effect
    def restrictive_policy_configuration(rule_configs)
      RepositoryRuleConfiguration.new(
        rule_type: :pull_request,
        parameters: {
          required_approving_review_count: rule_configs.map { |c| c.param("required_approving_review_count") }.max,
          require_code_owner_review: rule_configs.any? { |c| c.param("require_code_owner_review") },
          dismiss_stale_reviews_on_push: rule_configs.any? { |c| c.param("dismiss_stale_reviews_on_push") },
          ignore_approvals_from_contributors: rule_configs.any? { |c| c.param("ignore_approvals_from_contributors") },
          require_last_push_approval: rule_configs.any? { |c| c.param("require_last_push_approval") },
          required_review_thread_resolution: rule_configs.any? { |c| c.param("required_review_thread_resolution") }
        }
      )
    end

    def policy_required_and_fulfilled?(decision)
      decision.rules_fulfilled? &&
        decision.reason.code != :review_policy_not_required
    end

    # This does not appear to be used anywhere
    def pull_request_enqueued?
      return false if pull_request.blank?

      pull_request.merge_queue_enabled? && pull_request.in_merge_queue?
    end

    def relevant_merge_commit?(ref_update, rule_commit)
      rule_commit.merge_commit? &&
        rule_commit.parent_oids.include?(ref_update.before_oid)
    end

    # Private: Returns a Hash of the default data we want for the instrumentation payload
    # for a single Decision
    def default_instrumentation_payload(reviews)
      { review_ids: reviews.map(&:id) }
    end

    # Check the state of reviews for a ref_update that lives on a non protected branch.
    #
    # Returns a Decision
    def check_reviews_non_protected_branch(ref_update, reviews)
      summary, message = nil, nil
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

      Decision.success(ref_update,
        reason: {
          code: :review_policy_not_required,
          summary: summary,
          message: message,
        },
        instrumentation_payload: payload,
      )
    end

    def thread_resolution_policy_met?(rule_config, commit_oid)
      return true if !rule_config.param("required_review_thread_resolution")

      # Once branch protections are removed, we can move the function into this class
      discussion_policy = Rules::ThreadResolutionRule.new
      discussion_policy.validate_review_threads_are_resolved(repository, commit_oid)
    end

    # Private: Check policy for an Array of reviews for a ref_update
    #
    # Returns a Decision
    def check_reviews(ref_update, reviews, rule_config, commit_oid, consider_open_pulls_only)
      reason = :review_policy_not_satisfied
      rules_fulfilled = false
      summary, message = nil, nil
      payload = default_instrumentation_payload(reviews)
      required_approval_count = rule_config.param("required_approving_review_count")
      last_pusher_policy = last_pusher_policy_info(reviews, rule_config, commit_oid, consider_open_pulls_only)

      begin
        case
        when reviews.any?(&:changes_requested?)
          summary = "Changes requested"
          message = build_message(reviews) + " by reviewers with write access."
          payload[:has_requested_changes] = true
        when (waiting_on = code_owners_awaiting_review(ref_update, reviews, commit_oid, rule_config, consider_open_pulls_only)).any?
          summary = "Code owner review required"
          message = awaiting_code_owners_message(waiting_on)
          payload[:code_owner_review_required] = true
        when soc2_reason = awaiting_soc2_approval_process(reviews)
          summary = "Review from compliance team required"
          message = soc2_reason
          payload[:soc2_approval_process_required] = true
        when !thread_resolution_policy_met?(rule_config, commit_oid)
          summary = "Conversation resolution required"
          message = "A conversation must be resolved before this pull request can be merged."
          payload[:thread_resolution_required] = true
        when (merge_type_failed_reason = check_cli_merge_type(ref_update))
          if merge_type_failed_reason == :merge_commit_blocked
            summary = "Merge commit not allowed"
            message = "Merge commits are not allowed in this repository."
          elsif merge_type_failed_reason == :rebase_and_squash_merge_blocked
            summary = "Rebase and squash merge not allowed"
            message = "When rebase and squash merges are not allowed, a merge commit must be used."
          elsif merge_type_failed_reason == :rebase_blocked_squash_rejected
            summary = "Rebase merge not allowed"
            message = "When rebase merges are not allowed, merges must occur on the web#{repository.merge_commits_allowed? ? " or with a merge commit" : ""}."
          end
        when required_approval_count == 0 && !check_last_pusher(rule_config)
          # When we have to check for the last pusher, then we require at least 1 approval and skip this condition
          # A policy with 0 required approvals means direct pushes are blocked and a PR is required
          pull = begin
            if pull_request
              pull_request
            else
              repository.pull_requests.open_pulls.find_by(head_sha: commit_oid, base_ref: ref_update.branch_name, work_in_progress: false)
            end
          end

          if pull && !pull.draft?
            rules_fulfilled = true
            reason = :review_policy_not_required
            summary = "Approval not required"
            message = "This pull request may be merged without approvals."
          else
            rules_fulfilled = false
            summary = "Pull request required"
            message = "Changes must be made through a pull request."
          end
        when !last_pusher_policy.policy_met
          summary = "Review required"
          message = "New changes require approval from someone other than"
          if last_pusher_policy.last_push_user&.login
            message += " #{last_pusher_policy.last_push_user&.login} because they were the last pusher."
          else
            message += " the last pusher."
          end
          if last_pusher_policy.multiple_repository_prs_found
            GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.check_reviews.multiple_repository_prs_found")
            summary = "Multiple pull requests found"
            message = <<~MESSAGE.squish
              Last push branch protection does not allow multiple pull requests
              on the same commit from different repositories.
              Please close related PRs to proceed.
            MESSAGE
          elsif last_pusher_policy.push_not_found
            message += " The last push was not found for this branch."
          end
          payload[:last_push_approval_required] = true
          payload[:approving_reviews_required] = true
        when ((count = qualifying_approved_review_count(reviews, rule_config, commit_oid, consider_open_pulls_only)) >= required_approval_count)
          rules_fulfilled = true
          reason = :review_approved
          summary = "Changes approved"
          message = build_message(reviews) + " by reviewers with write access."
        else
          summary = "Review required"
          message = <<~MESSAGE.squish
            At least #{required_approval_count}
            #{"approving review".pluralize(required_approval_count)}
            #{"is".pluralize(required_approval_count)}
            required by reviewers with write access.
          MESSAGE
          if (disqualified_reviews = check_ignore_approvers_disqualified_reviews(reviews, rule_config, commit_oid, consider_open_pulls_only)).any?
            # this condition is evaluted only if ignore_approvals_from_contributors is enabled
            # and there are some reviews that are disqualified
            disqualified_count = disqualified_reviews.size
            payload[:disqualified_review_ids] = disqualified_reviews.map(&:id)
            message = <<~MESSAGE.squish
              At least #{required_approval_count}
              #{"approving review".pluralize(required_approval_count)}
              #{"is".pluralize(required_approval_count)}
              required by reviewers with write access who have not pushed changes
              to this pull request after it was opened.
              #{disqualified_count} #{"review".pluralize(disqualified_count)}
              from #{disqualified_reviews.map { |r| "'#{r.user.login}'" }.sort.uniq.to_sentence }
              #{ "was".pluralize(disqualified_count) } disqualified because of a subsequent push.
            MESSAGE
          end
          payload[:approving_reviews_required] = true
          payload[:approving_reviews_count] = count
        end
      rescue PullRequest::DetermineCodeownersError
        summary = "Code owner review required"
        message = "Could not determine code owners from the current diff."
        payload[:code_owner_review_required] = true
      rescue MultiplePullRequestsFoundError
        GitHub.dogstats.increment("repository_rules_engine.rule.pull_request.check_reviews.multiple_repository_prs_found")
        summary = "Multiple pull requests found"
        message = <<~MESSAGE.squish
          Found multiple pull requests
          on the same commit from different repositories.
          Please close related PRs to proceed.
        MESSAGE
        payload[:approving_reviews_required] = true
      end

      if repository.feature_enabled?(:log_pr_cli_pushes) && @cli_merge && ref_update.is_a?(Git::Ref::Update)
        any_merge_types_blocked = !repository.merge_commit_allowed? || !repository.rebase_commits_allowed? || !repository.squash_commits_allowed?

        behind, ahead = if any_merge_types_blocked
          GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.commit_ahead_count") do
            comparison = GitHub::Comparison.deprecated_build(repository, ref_update.refname, ref_update.after_oid)
            comparison.valid? ? comparison.relationship.map(&:to_i) : [0, 0]
          end
        else
          [0, 0]
        end

        is_merge_commit = ref_update.after_commit&.parent_oids&.count > 1
        merge_commit_rule_allowed = repository.merge_commits_allowed? ? true : !is_merge_commit
        # For rebases, the only way a rebase would make it to this point is if the PR itself was up to date. Otherwise, we would
        # not be able to lookup the PR by the head of the PR branch. Therefore, any non-merge commit fast forward should be considered a "rebase".
        # The exception is if squash commits are allowed. In that case, we allow any single-commit fast forwards.
        # Traditional squashes are not supported by the CLI since we cannot look up the PR by a user created squash commit.
        fast_forward_rule_allowed = if repository.rebase_commits_allowed?
          true
        else
          is_merge_commit || (repository.squash_commits_allowed? && ahead == 1)
        end

        GitHub.dogstats.increment("repository_rules_engine.pr_cli_pushes", tags: [
          "result:#{rules_fulfilled}",
          "merge_allowed:#{repository.merge_commit_allowed?}",
          "rebase_allowed:#{repository.rebase_commits_allowed?}",
          "squash_allowed:#{repository.squash_commits_allowed?}",
          "merge_commit:#{is_merge_commit}",
          "would_block:#{!merge_commit_rule_allowed || !fast_forward_rule_allowed}",
        ])

        if any_merge_types_blocked
          GitHub.logger.info("PR CLI merge with merge types disabled", {
            "code.namespace": self.class.name,
            "code.function": __method__,
            "gh.repo.id": repository.id,
            "gh.owner.id": repository.owner&.id,
            "gh.branch_protection_rule.result": rules_fulfilled,
            "gh.branch_protection_rule.commits_ahead": ahead,
            "gh.branch_protection_rule.commits_behind": behind,
            "gh.branch_protection_rule.merge_commit_allowed": repository.merge_commit_allowed?,
            "gh.branch_protection_rule.rebase_commits_allowed": repository.rebase_commits_allowed?,
            "gh.branch_protection_rule.squash_commits_allowed": repository.squash_commits_allowed?,
            "gh.branch_protection_rule.is_merge_commit": is_merge_commit,
            "gh.branch_protection_rule.would_block_merge_commit": !merge_commit_rule_allowed,
            "gh.branch_protection_rule.would_block_non_merge_commit": !fast_forward_rule_allowed,
          })
        end
      end

      Decision.new(ref_update, rules_fulfilled,
        reason: {
          code: reason,
          summary: summary,
          message: message,
          instrumentation_payload: payload
        },
        instrumentation_payload: payload
      )
    end

    sig { params(ref_update: T.any(Git::Ref::Update, Git::Ref::Update::Null)).returns(T.nilable(Symbol)) }
    def check_cli_merge_type(ref_update)
      return unless repository.feature_enabled?(:pr_rule_global_merge_types_enforce) && @cli_merge && ref_update.is_a?(Git::Ref::Update)

      is_merge_commit = ref_update.after_commit&.parent_oids&.count > 1
      if !repository.merge_commits_allowed? && is_merge_commit
        :merge_commit_blocked
      elsif !repository.rebase_commits_allowed? && !is_merge_commit
        behind, ahead = GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.commit_ahead_count") do
          comparison = GitHub::Comparison.deprecated_build(repository, ref_update.refname, ref_update.after_oid)
          comparison.valid? ? comparison.relationship.map(&:to_i) : [0, 0]
        end
        if repository.squash_commits_allowed?
          ahead == 1 ? nil : :rebase_blocked_squash_rejected
        else
          :rebase_and_squash_merge_blocked
        end
      end
    end

    # Generate an approval decision which summarizes multiple approved pull request branch protections
    def summarized_approval_decision(ref_update, reviews, rule_configs)
      reason = if rule_configs.any? { |c| c.param("required_approving_review_count") > 0 }
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

      Decision.success(ref_update,
        reason: reason,
        instrumentation_payload: default_instrumentation_payload(reviews)
      )
    end

    def qualifying_approved_review_count(reviews, rule_config, commit_oid, consider_open_pulls_only)
      if rule_config.param("ignore_approvals_from_contributors")
        disqualified_user_ids = contributing_user_ids(commit_oid, consider_open_pulls_only, reviews)
        reviews.select { |r| r.approved? && !disqualified_user_ids.include?(r.user_id) }.uniq(&:user_id).count
      else
        reviews.select(&:approved?).uniq(&:user_id).count
      end
    end

    # disqualified reviews exist if policy config set to ignore approvals from contributors to the PR
    def check_ignore_approvers_disqualified_reviews(reviews, rule_config, commit_oid, consider_open_pulls_only)
      if rule_config.param("ignore_approvals_from_contributors")
        disqualified_user_ids = contributing_user_ids(commit_oid, consider_open_pulls_only, reviews)
        reviews.select { |r| disqualified_user_ids.include?(r.user_id) }
      else
        []
      end
    end

    class LastPushPolicyResult
      attr_accessor :policy_met, :last_push_user, :push_not_found, :multiple_repository_prs_found

      def initialize(policy_met:, last_push_user: nil, multiple_repository_prs_found: false, push_not_found: false)
        @policy_met = policy_met
        @last_push_user = last_push_user
        @push_not_found = push_not_found
        @multiple_repository_prs_found = multiple_repository_prs_found
      end
    end

    # Whether or not to verify the last pusher by looking at the last reviewable commit
    def last_reviewable_commit_enabled?
      GitHub.flipper[:last_reviewable_commit].enabled?(repository) ||
      GitHub.flipper[:last_reviewable_commit].enabled?(repository.owner)
    end

    # Private: return true if we need to check for who made the last push
    def check_last_pusher(rule_config)
      rule_config.param("require_last_push_approval")
    end

    def head_repositories(reviews)
      return [pull_request.head_repository] if pull_request
      reviews.map { |r| r.pull_request.head_repository }.uniq
    end

    # Private: Look up info for last pusher policy.
    #
    # A full result is returned at once to avoid multiple lookups
    # Since multiple people can push up the same commit via different branches, caching isn't an option
    # Returns LastPushPolicyResult
    def last_pusher_policy_info(reviews, rule_config, commit_oid, consider_open_pulls_only)
      # Return as true if we don't need to check for the last pusher
      return LastPushPolicyResult.new(policy_met: true) unless check_last_pusher(rule_config)

      # If we have no reviews and no pull request, we should return here since we won't find a last pusher without one of them.
      # We know the policy is not met if there are no reviews, since at least 1 approval is required
      # by someone who isn't the last pusher
      return LastPushPolicyResult.new(policy_met: false) if reviews.blank? && pull_request.nil?

      # check for reviews from multiple repositories
      head_repos = head_repositories(reviews)
      return LastPushPolicyResult.new(policy_met: false, multiple_repository_prs_found: true) if head_repos.count > 1

      unless repository.async_scoped_feature_flag_enabled?(:find_last_push_without_approvals)&.sync
        # new code: put behind feature flag
        if last_reviewable_commit_enabled?
          num_approvals = reviews.count { |review| review.approved? }

          # If there are no approvals, then the policy is unfulfilled
          return LastPushPolicyResult.new(policy_met: false) if num_approvals == 0
        end
      end

      last_push = last_push_for_commit(commit_oid, consider_open_pulls_only, head_repos.first, reviews)

      if !last_push
        # We weren't able to find the commit on the Pushes table
        # One known scenario where this could happen is when we don't have a head repo,
        # which can occur because PRs can have foreign keys to repos that may have been deleted.
        # For any reason, if we can't find the push, disqualify all reviews and do not allow the rule to pass
        GitHub.logger.info("Unable to find Push record for commit", {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository.id,
          "git.commit.oid": commit_oid,
        })

        LastPushPolicyResult.new(policy_met: false, push_not_found: true)
      else
        pushed_at = last_push.pushed_at || last_push.created_at
        result = reviews.count { |r| last_push.pusher_id != r.user_id && r.submitted_at > pushed_at && r.approved? }
        LastPushPolicyResult.new(policy_met: result > 0, last_push_user: User.find_by(id: last_push.pusher_id))
      end
    end

    def soc2_approval_process_required?
      !GitHub.enterprise? && SOC2_REPOS.include?(repository.name_with_owner)
    end

    # Private: Check if this policy fails due to Soc 2 review policy compliance not being fulfilled.
    #
    # Soc 2 review process requires that an review is requested to a team ending with '-reviewers' and
    # that at least one of those requests has been fulfilled via an approval review.
    #
    # reviews - An Array of PullRequestReviews that are considered for this policy check.
    #
    # Returns a reason String why Soc 2 compliance is not fulfilled or nil if it is fulfilled.
    def awaiting_soc2_approval_process(reviews)
      return unless soc2_approval_process_required?

      if pull_request
        soc2_check_for_pull(pull_request, reviews)
      else
        soc2_check_for_ref_update(reviews)
      end
    end

    def soc2_check_for_pull(pull_request, reviews)
      requests = soc2_review_requests(pull_request)

      if requests.none?
        "Waiting on review request to a compliance team (i.e. '@github/*-reviewers')"
      elsif filter_requests_fulfilled_by(requests, reviews).none?
        compliance_teams = requests.map { |req| req.reviewer.to_s }
        compliance_teams = compliance_teams.uniq.to_sentence \
          two_words_connector: " or ",
          last_word_connector: ", or "
        "Waiting on approval from at least one compliance team: #{compliance_teams}."
      end
    end

    def soc2_check_for_ref_update(reviews)
      fulfilled_requests = reviews.flat_map do |review|
        review.review_requests.includes(:reviewer)
      end.uniq
      fulfilled_soc2_requests = filter_soc2_review_requests(fulfilled_requests)

      if fulfilled_soc2_requests.none?
        "Waiting on review request to and subsequent approval from a compliance team (i.e. '@github/*-reviewers')"
      end
    end

    # Private: Finds any review requests for this PR which are requested for review compliance teams.
    #
    # Returns an Array of ReviewRequests.
    def soc2_review_requests(pull_request)
      review_requests = pull_request.review_requests.not_dismissed.includes(:reviewer, :pull_request_reviews)
      filter_soc2_review_requests(review_requests)
    end

    def filter_soc2_review_requests(review_requests)
      review_requests.select do |request|
        request.reviewer.is_a?(Team) && request.reviewer.slug =~ SOC2_REVIEWERS_TEAM_PATTERN
      end
    end

    def filter_requests_fulfilled_by(requests, reviews)
      requests.select { |request| (request.pull_request_reviews & reviews).any? }
    end

    def code_owners_awaiting_review(ref_update, reviews, commit_oid, rule_config, consider_open_pulls_only)
      return [] unless rule_config&.param("require_code_owner_review")

      GitHub.dogstats.distribution_time("repository_rules_engine.rule.pull_request.find_code_owners_awaiting_review", tags: ["strict:false"]) do
        find_code_owners_awaiting_review(ref_update, reviews, commit_oid, consider_open_pulls_only)
      end
    end

    def find_code_owners_awaiting_review(ref_update, reviews, commit_oid, consider_open_pulls_only)
      reviewer_ids = reviews.map(&:user_id)
      codeowners = if pull_request
        pull_request.codeowners!
      else
        Repository::Codeowners.new(repository, ref: ref_update.refname,  paths: ref_update.paths)
      end

      pull_request_author_ids = if pull_request
        [pull_request.user_id]
      else
        pull_author_ids(commit_oid, consider_open_pulls_only)
      end

      codeowners.owners_by_rule.each_with_object(Set.new) do |(_rule, owners), awaiting|
        # Don't block if the PR author is a required code owner. They aren't
        # allowed to review their own PR and being the author fulfills the
        # spirit of enforced code owners.
        owners.reject! { |o| o.instance_of?(User) && pull_request_author_ids.include?(o.id) }

        awaiting.merge(owners) unless code_owner_reviewed?(owners, reviewer_ids)
      end
    end

    def code_owner_reviewed?(owners, reviewer_ids)
      teams, users = owners.partition { |o| o.is_a?(Team) }
      return true if (reviewer_ids & users.map(&:id)).any?

      team_member_ids = Team.members_of(teams.map(&:id), immediate_only: false).pluck(:id)
      (reviewer_ids & team_member_ids).any?
    end

    def awaiting_code_owners_message(waiting_on)
      # Only show the first 10 codeowners to prevent truncation of rule message
      overflow = waiting_on.size > 10
      phrase = waiting_on.take(10).map(&:to_s).sort
        .to_sentence(two_words_connector: " and/or ", last_word_connector: overflow ? ", " : ", and/or ") +
        (overflow ? ", and/or #{waiting_on.size - 10} others" : "")

      "Waiting on code owner review from #{phrase}."
    end

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

    def policy_commit_for(ref_update)
      if ref_update.respond_to?(:rule_commit)
        ref_update.rule_commit
      else
        ref_update.after_commit
      end
    end

    # Private: Find relevant RepositoryRuleConfigurations for a ref_update
    def find_pull_request_policies(ref_update)
      policies_by_refname[ref_update.refname] if repository.supports_protected_branches?
    end
  end
end
