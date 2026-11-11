# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    class CompareStaleMergeCommitJob < ApplicationJob
      MAX_PUSH_COUNT = 20

      locked_by timeout: 30.minutes, key: ->(job) {
        pull_request = job.arguments.first
        pull_request.id
      }

      queue_as :synchronize_pull_request

      # No retries
      discard_on(StandardError) do |_job, error|
        Failbot.report(error)
      end

      sig do params(
        pull_request: ::PullRequest,
        merge_sha: String)
        .void
      end
      public_class_method def self.queue_future_run(pull_request:, merge_sha:)
        return unless FeatureFlag.vexi.enabled?(:compare_stale_merge_job_enabled, pull_request.repository, default: false)

        return unless FeatureFlag.vexi.enabled?(:compare_stale_merge_job_percent, default: false) ||
          # This flag lets use set some actors to "100%" even if the world at large is at 5%. It basically lets us staff-ship.
          pull_request.repository&.async_scoped_feature_flag_enabled?(:compare_stale_merge_job_always_queue)&.sync

        GitHub.dogstats.increment("compare_stale_merge_job_queue", tags: [])

        # Percents can be set to two decimals, so we have 0.01 hour (== 36 seconds) resolution
        minimum_delay_hours = FeatureFlag.vexi.percentage_of_calls_value_or_raise(:compare_stale_merge_job_min_delay) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
        maximum_delay_hours = FeatureFlag.vexi.percentage_of_calls_value_or_raise(:compare_stale_merge_job_max_delay) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage

        gap = maximum_delay_hours - minimum_delay_hours

        delay = minimum_delay_hours + (Random.rand * gap)
        delay = Float(0.1) if delay < 0.1
        delay = Float(24) if delay > 24.0
        delay = delay.hours

        CompareStaleMergeCommitJob
          .set(wait_until: DateTime.now + delay)
          .perform_later(pull_request, stale_merge_sha: merge_sha)
      end

      sig do params(
        pull_request: ::PullRequest,
        stale_merge_sha: String)
        .void
      end
      def perform(pull_request, stale_merge_sha:)
        # Tags for the datadog entry
        tags = T.let({}, T::Hash[String, T.untyped])
        tags["compare_result"] = "unknown"

        # Properties for the log entry
        log_props = T.let({}, T::Hash[String, T.untyped])
        log_props["gh.pull_request.id"] = pull_request.id
        log_props["gh.repo.id"] = pull_request.repository_id
        log_props["gh.pull_request.base_ref"] = pull_request.base_ref_name
        log_props["gh.pull_request.head_ref"] = pull_request.head_ref_name
        log_props["gh.job.stale_merge_sha"] = stale_merge_sha

        tags["job_result"] = compare_merge_commits(pull_request, stale_merge_sha, tags, log_props)

        GitHub.dogstats.increment("compare_stale_merge_job_result", tags: tags.map { |k, v| "#{k}:#{v}" })

        log_props.merge!(tags)
        GitHub.logger.info("Stale merge commit compare", **log_props)
      end

      sig do params(
        pull_request: ::PullRequest,
        stale_merge_sha: String,
        tags: T::Hash[String, T.untyped],
        log_props: T::Hash[String, T.untyped])
        .returns(Symbol)
      end
      def compare_merge_commits(pull_request, stale_merge_sha, tags, log_props)
        ###
        ### Determine if reusing merge would even be a possibility
        ###

        return :pull_closed if pull_request.closed?

        return :unmergeable if pull_request.currently_mergeable? == false

        return :no_current_merge if pull_request.merge_commit_sha.nil? || pull_request.merge_commit_sha == GitHub::NULL_OID
        log_props["gh.job.current_merge_sha"] = current_merge_sha = T.cast(pull_request.merge_commit_sha, String)

        return :stale_merge_is_current if pull_request.merge_commit_sha == stale_merge_sha

        promise_sync = Promise.all([
          pull_request.async_repository,
          pull_request.async_batch_base_branch_rule_evaluator,
          pull_request.async_user,
        ]).sync

        return :no_repository unless promise_sync[0]
        repository = T.let(promise_sync[0], Repository)
        log_props["gh.repo.name"] = repository.try(:name)
        log_props["gh.repo.public"] = repository.try(:public?) || false
        log_props["gh.repo.owner.id"] = repository.try(:owner).try(:id)
        log_props["gh.repo.owner.login"] = repository.try(:owner).try(:display_login)
        log_props["gh.pull_request.base_sha"] = repository.refs["refs/heads/#{pull_request.base_ref_name}"]&.target_oid || "nil"
        log_props["gh.pull_request.head_sha"] = repository.refs["refs/heads/#{pull_request.head_ref_name}"]&.target_oid || "nil"

        return :no_branch_evaluator unless promise_sync[1]
        base_branch_rule_evaluator = T.let(promise_sync[1], BranchRuleEvaluator)

        return :no_rules if base_branch_rule_evaluator.ref_rulesets.empty? && base_branch_rule_evaluator.protected_branch.nil?

        user = T.let(promise_sync[2] || User.ghost, User)
        default_merge_method = base_branch_rule_evaluator.default_merge_method_for(user) || repository.default_merge_method_for(user)

        stale_merge_commit, current_merge_commit = begin
          commits = repository.commits.find([stale_merge_sha, current_merge_sha])
          [T.cast(commits.first, Commit), T.cast(commits.second, Commit)]
        rescue GitRPC::ObjectMissing => ex
          return :commit_not_found
        end

        # Real-time interval between creation of the stale and current merges; bucket to nearest half-hour
        age_sec = current_merge_commit.created_at - stale_merge_commit.created_at
        tags["stale_merge_age_minutes"] = (age_sec / 1800.0).to_i * 30

        # Even though merges are tree-equal, it's possible we will get rule disagreements because of e.g., statuses posted
        # to one commit but not the other.
        tags["stale_merge_tree_equal"] = current_merge_commit.tree_oid == stale_merge_commit.tree_oid

        # Find all the parents. Parent1 is the base branch at the time the merge was created, and parent2 the head branch.
        stale_merge_parent1_sha, stale_merge_parent2_sha = stale_merge_commit.parent_oids
        current_merge_parent1_sha, current_merge_parent2_sha = current_merge_commit.parent_oids

        if stale_merge_parent2_sha != current_merge_parent2_sha
          # Head branch of the PR was updated after the stale merge was created -- new merge should be created regardless
          return :head_branch_updated
        end

        ahead_behind = repository.spokes_api.ahead_behind(base: current_merge_parent1_sha, tips: [stale_merge_parent1_sha])
        ahead = T.cast(ahead_behind.first.second.first, Integer)
        behind = T.cast(ahead_behind.first.second.second, Integer)

        tags["stale_merge_behind"] = behind

        if ahead > 0
          # The stale-merge parent1 is AHEAD of the current-merge parent1.
          # That means commits have been removed or rolled back from the base branch since the stale merge was created.
          # We should never reuse a merge which includes commits which were undone / rolled back.
          return :stale_merge_contains_rollback
        end

        # Find the best-merge-bases of both stale and current merge commits
        stale_merge_base_sha, current_merge_base_sha = Promise.all([
          pull_request.async_find_best_merge_base_sha(base_sha: stale_merge_parent1_sha, head_sha: stale_merge_parent2_sha),
          pull_request.async_find_best_merge_base_sha(base_sha: current_merge_parent1_sha, head_sha: current_merge_parent2_sha),
        ]).sync
        return :merge_base_not_found unless stale_merge_base_sha && current_merge_base_sha
        # Merge-base moved even though head branch did not -- new merge should be created regardless
        return :merge_base_moved unless stale_merge_base_sha == current_merge_base_sha

        ###
        ### Evaluate rules twice; one with stale merge commit and again with current merge.
        ###

        # Where we are at: we have a newer "current" merge and an older "stale" merge. The merge-base and head branch are
        # the same for both merges, however the base branch has moved. The base branch has only moved forward since the
        # stale merge was created. This is a situation where we could, potentially, reuse the stale merge commit.

        if FeatureFlag.vexi.enabled?(:compare_stale_merge_job_count_pushes, default: false)
          # Count how many pushes have been made to the base branch since the stale merge was created. This is different than
          # the behind count, because one push can add any number of commits to the branch. Unfortunately, the public Pushes
          # interface doesn't have a great query to use here -- we really just want a count.
          push_records = Repositories.domain.pushes.by_repository_id_and_refs(
            repository_id: repository.id,
            refs: [pull_request.qualified_base_ref_name],
            limit: MAX_PUSH_COUNT)
          push_count = push_records.find_index do |push|
            push.after == stale_merge_parent1_sha || push.pushed_at <= stale_merge_commit.created_at
          end
          tags["stale_push_count"] = push_count || MAX_PUSH_COUNT
        end

        # should always be true once we reach this point in the job
        is_out_of_date = pull_request.current_base_sha != stale_merge_parent1_sha

        stale_ref_update = Git::Branch::Update.new(
          repository: repository,
          refname:  "refs/heads/#{pull_request.base_ref_name}",
          before_oid: stale_merge_parent1_sha,
          after_oid: stale_merge_sha,
          pull_request: pull_request,
          merge_method: default_merge_method,
          is_out_of_date_cached_merge: is_out_of_date)

        current_ref_update = Git::Branch::Update.new(
          repository: repository,
          refname:  "refs/heads/#{pull_request.base_ref_name}",
          before_oid: current_merge_parent1_sha,
          after_oid: current_merge_sha,
          pull_request: pull_request,
          merge_method: default_merge_method)

        # Optionally, set the PR "merge commit" to the stale merge while evaluating rules, on the off chance that any
        # rules key off that value
        fake_merge_sha = FeatureFlag.vexi.enabled?(:compare_stale_merge_job_fake_merge_commit, repository, default: false)
        pull_request.merge_commit_sha = stale_merge_sha if fake_merge_sha

        # Evaluate all rules using the stale merge commit from when this job was queued
        stale_suite = RuleEngine::Evaluator.evaluate_rules(repository, [stale_ref_update], user, dry_run: true)
        pull_request.merge_commit_sha = current_merge_sha if fake_merge_sha
        stale_suite.each(&:log_evaluation)

        # Now evaluate all rules using the up-to-date merge commit
        current_suite = RuleEngine::Evaluator.evaluate_rules(repository, [current_ref_update], user, dry_run: true)
        current_suite.each(&:log_evaluation)

        ###
        ### Analyze / compare rule eval results
        ###

        if FeatureFlag.vexi.enabled?(:compare_stale_merge_job_advanced_diff, default: false)
          tags["advanced_rule_suite_diff"] = true
          return :rules_modified if deep_compare_rule_suites(stale_suite, current_suite, tags)
        end

        # Rule evaluation fails if any one of the rulesets fails
        stale_failed = stale_suite.any?(&:failed?)
        stale_bypassed = !stale_failed && stale_suite.any?(&:bypassed?)

        current_failed = current_suite.any?(&:failed?)
        current_bypassed = !current_failed && current_suite.any?(&:bypassed?)

        tags["stale_result"] = case
        when stale_failed
          "failed"
        when stale_bypassed
          "bypassed"
        else
          "allowed"
        end

        tags["current_result"] = case
        when current_failed
          "failed"
        when current_bypassed
          "bypassed"
        else
          "allowed"
        end

        tags["compare_result"] = case
        when stale_failed && current_failed
          "agree"
        when stale_failed && !current_failed
          "red_green"
        when current_failed
          "green_red"
        when stale_bypassed != current_bypassed
          # Neither failed, but one requires bypass and other doesn't
          "bypass_disagree"
        else
          "agree"
        end

        :compared
      end

      # Returns true if it detects the rules / branch protections were modified between evaluation runs.
      sig do params(
        stale_suite: T::Array[RuleEngine::RuleSuite],
        current_suite: T::Array[RuleEngine::RuleSuite],
        tags: T::Hash[String, T.untyped])
        .returns(T::Boolean)
      end
      def deep_compare_rule_suites(stale_suite, current_suite, tags)
        # Match stale and current rule runs using this tuple:
        #   [rule_provider, rule_type, repository_rule_configuration_id, rule_history_id]
        # Protected branches will not have a config id, but since only one can apply, the combination of
        #   [rule_provider (== "protected_branch"), rule_type] is unique.

        stale_rule_runs = stale_suite.map { _1.rule_runs }.flatten
          .group_by { [_1.rule_provider, _1.rule_type, _1.repository_rule_configuration_id, _1.rule_history_id] }
        current_rule_runs = current_suite.map { _1.rule_runs }.flatten
          .group_by { [_1.rule_provider, _1.rule_type, _1.repository_rule_configuration_id, _1.rule_history_id] }

        # If the rules and/or branch protections are not precisely the same for both eval runs, the results of those runs
        # are not really comparable because the rules themselves were modified between runs. Including the config_id in
        # the tuple means that even if all the same rules apply but one has been modified, this will fail.
        return true if stale_rule_runs.keys.sort != current_rule_runs.keys.sort

        stale_rule_runs.each do |key, val|
          stale_run = val.first
          current_run = current_rule_runs[key]&.first

          next if stale_run&.result == current_run&.result

          # This rule had a mismatch
          rule_type = key[1]
          increment(tags, "#{rule_type}_#{stale_run&.result}_#{current_run&.result}_mismatches")

          config = stale_run&.rule_config
          next unless config

          case rule_type
          when "pull_request"
            increment(tags, "require_code_owner_review_mismatches") if config.parameters["require_code_owner_review"]
            increment(tags, "required_reviewers_mismatches") if config.parameters["required_reviewers"].any?
          when "required_status_checks"
            increment(tags, "strict_required_status_checks_policy_mismatches") if config.parameters["strict_required_status_checks_policy"]
          end
        end

        false
      end

      sig { params(hash: T::Hash[String, T.untyped], key: String).void }
      private def increment(hash, key)
        hash[key] = (hash[key] || 0) + 1
      end
    end
  end
end
