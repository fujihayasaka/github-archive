# typed: true
# frozen_string_literal: true

class PullRequest
  class BatchMerge
    include ActiveModel::Validations

    attr_reader :base_repository, :pull_requests, :actor, :method, :message_title, :message

    validates :base_repository, :pull_requests, :actor, presence: true
    validate :pull_requests_must_be_mergeable, if: :base_repository

    # Create a new BatchMerge object, which allows merging multiple private PRs.
    #
    # This operates on security workspace PRs which are unique in 3 ways:
    # - They're always cross-repository. The base and head repos are never the same.
    # - They're "inverted:" they exist in the head repo and are merged into the base repo.
    # - The base and head repos are always in distinct networks such that objects aren't shared.
    #
    # Arguments:
    #
    # base_repository - The Repository into which all the PRs will be merged.
    # pull_requests   - An array of PullRequests to be merged. They must all exist in the same
    #                   repository, distinct from the base_repository, or an ArgumentError will be
    #                   raised.
    # actor           - The User performing the merge.
    # method          - Symbol that specifies the merge method to perform. Can be one of
    #                   :merge, :squash or :rebase. (optional, defaults to :merge).
    # message_title   - String commit message title to prefix the merge message
    #                   (optional, defaults to the default "
    #                   Merge pull request #N from repo/branch" text).
    # message         - String commit message to append to the merge message
    #                   (optional, defaults to PR title).
    def initialize(base_repository, pull_requests, actor, method: :merge, message_title: nil, message: nil)
      @base_repository = base_repository
      @pull_requests = pull_requests
      @actor = actor
      @method = method
      @message_title = message_title
      @message = message
    end

    # Perform the batch merge.
    #
    # Returns an array of two items [success, pulls]
    # - success: A boolean indicating if every merge succeeded.
    # - pulls: A hash keyed by PullRequest.
    #          If all merges succeeded:
    #             { PullRequest: PerformSuccessResult }
    #          If at least one merge failed, failing PRs are listed:
    #             { PullRequest: PullRequest::Merge::FailResult }
    def perform
      validate! # domain-isolation-query-violation:ignore:packages/issues (SELECT)

      merges = pull_requests.map do |pull_request|
        Merge.new(pull_request, method, actor, message_title: message_title, message: message)
      end

      prepare_and_validate_results = merges.map do |merger|
        [merger.pull, merger.prepare_and_validate(actor:)]
      end.to_h

      failures = prepare_and_validate_results.reject { |_, result| result.success }
      return [false, failures] if failures.any?

      perform_merge_results = merges.map do |merger|
        [merger.pull, merger.perform]
      end.to_h

      failures = perform_merge_results.reject { |_, result| result.success }
      return [false, failures] if failures.any?

      ref_update_specs = perform_merge_results.map do |pull_request, result|
        [pull_request.merge_ref, nil, result.new_sha]
      end

      failures = validate_rule_bypass(pull_requests)
      return [false, failures] if failures.any?

      pull_requests.first.head_repository.batch_write_refs(actor, ref_update_specs)

      fetch_changes_into_base_repo

      merged_at, failures = base_repo_ref_updates(merges, perform_merge_results)

      return [false, failures] if failures.any?

      post_merge(merges, prepare_and_validate_results, perform_merge_results, merged_at)

      result = merges.map do |merger|
        pull_request = merger.pull

        [pull_request, PerformSuccessResult.new("refs/heads/#{pull_request.base_ref_name}", merger.merge_base_sha, perform_merge_results[pull_request].new_sha)]
      end.to_h

      [true, result]
    end

    class PerformSuccessResult < PullRequest::Merge::PerformSuccessResult
      attr_reader :base_sha, :base_ref

      def initialize(base_ref, base_sha, new_sha)
        super(new_sha)
        @base_sha = base_sha
        @base_ref = base_ref
      end

    end

    private

    def pull_requests_must_be_mergeable
      error, details = catch :error do
        base_refs = Set.new
        head_repository_ids = Set.new

        pull_requests.each do |pull_request|
          head_repository_ids << pull_request.head_repository_id

          # Check that every pull request's base repository is the same as the
          # base_repository passed when the batch merge was instantiated.
          if pull_request.base_repository_id != base_repository.id
            throw :error, [:invalid_base_repository, {}]
          end

          # Check that any single branch on the base repository is targeted only
          # once in the collection of pull requests. Otherwise, merge chaos
          # would ensue.
          if base_refs.include?(pull_request.base_ref)
            throw :error, [:duplicate_base_ref, {
              base_ref_name: pull_request.base_ref_name,
            }]
          else
            base_refs << pull_request.base_ref
          end
        end

        # Check that the only head repository is a security workspace cut from
        # the base_repository passed when the batch merge was instantiated.
        if head_repository_ids.size == 1
          advisory_repository = pull_requests.first.head_repository&.
            parent_advisory_repository

          if advisory_repository.nil?
            throw :error, [:missing_advisory, {}]
          elsif advisory_repository != base_repository
            throw :error, [:invalid_head_repository, {}]
          end
        # Check that every pull request has the same head repository.
        elsif head_repository_ids.size > 1
          throw :error, [:multiple_head_repositories, {
            head_repository_ids: head_repository_ids.to_a,
          }]
        end

        return # If we get this far, all pull requests are mergeable!
      end

      errors.add(:base, error, **details)
    end

    # `BatchMerge` operates only on security workspace PRs. A security workspace repository is in
    # its own netweork, distinct from the upstream repository from which is was created: their git
    # objects are not shared by design. So unlike typical forks, we must explicitly transfer
    # relevant commits to the base repo before merging.
    def fetch_changes_into_base_repo
      pull_requests.each do |pull_request|
        pull_request.base_repository.rpc.fetch(
          pull_request.head_repository.internal_remote_url,
          refspec: pull_request.merge_ref,
        )
      end
    end

    def base_repo_ref_updates(merges, perform_merge_results)
      ref_updates = merges.map do |merger|
        pull_request = merger.pull

        ["refs/heads/#{pull_request.base_ref_name}", merger.merge_base_sha, perform_merge_results[pull_request].new_sha]
      end

      branch_updates = ref_updates.map do |ref_update|
        Git::Branch::Update.new(repository: base_repository, refname: ref_update.first, before_oid: ref_update.second, after_oid: ref_update.last,)
      end

      suites = RuleEngine::Evaluator.evaluate_rules(base_repository, branch_updates, actor, dry_run: true) if is_rule_evaluation_enabled?

      if suites.present?
        failures = suites.each_with_index.filter_map do |suite, index|
          next nil if suite.action_permitted?

          [merges[index].pull, PullRequest::Merge::FailResult.new("Repository rule violations found.", :repository_rule_violation)]
        end.to_h

        return [false, failures] if failures.any?
      end

      result = [base_repository.batch_write_refs(actor, ref_updates), []]

      if suites.present?
        # HACK: This is normally done when evaluating rules, but we only want to persist these
        # results if the merge is successful.
        ProtectedBranchLegacyInstrumenter.instrument_decision(suites, base_repository)
        suites.each(&:log_evaluation)

        suites.filter(&:should_persist?).each(&:save!)
      end

      result
    end

    def post_merge(merges, prepare_and_validate_results, perform_merge_results, merged_at)
      PullRequest.transaction do
        pull_requests.each do |pull_request|
          validate_result = prepare_and_validate_results[pull_request]
          merge_commit = validate_result.merge_commit
          merge_base_ref = validate_result.merge_base_ref

          perform_result = perform_merge_results[pull_request]
          new_sha = perform_result.new_sha

          pull_request.post_merge(actor, merge_commit, merge_base_ref, new_sha, merged_at, method, :direct_merge)
        end
      end
    end

    def validate_rule_bypass(pull_requests)
      return {} unless is_rule_evaluation_enabled?

      evaluators = BranchRuleEvaluator.for_repository_with_branch_names(base_repository, pull_requests.map(&:base_ref_name))

      pull_requests.filter_map do |pull_request|
        next unless evaluators.key?(pull_request.base_ref_name)

        targetable = RuleEngine::Conditions::Targets::Repository.new(repository: base_repository)
        enabled_rules = T.must(evaluators[pull_request.base_ref_name]).rule_configs.select { |config| config.enabled? && !config.can_skip?(actor, targetable) }
        next if enabled_rules.all? do |rule|
          next true if rule.provider_name == "protected_branch"

          rule.can_bypass?(actor, targetable)
        end

        [pull_request, PullRequest::Merge::FailResult.new("Only someone that can bypass branch protections can merge.", :repository_rule_violation)]
      end.to_h
    end

    def is_rule_evaluation_enabled?
      return false if base_repository.async_scoped_feature_flag_enabled?(:security_advisory_rule_evaluation_opt_out).sync

      base_repository.async_scoped_feature_flag_enabled?(:security_advisory_rule_evaluation).sync
    end
  end
end
