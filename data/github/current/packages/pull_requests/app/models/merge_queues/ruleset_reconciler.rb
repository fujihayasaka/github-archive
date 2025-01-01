# typed: strict
# frozen_string_literal: true

module MergeQueues
  # This class is reponsible for making sure that the merge queues
  # configured via rulesets for a given repository exist. It will create or
  # delete queues as required to match the current configuration.
  class RulesetReconciler
    include GitHub::Memoizer

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig { void }
    def reconcile_all
      branches_needing_merge_queues = targeted_branch_names
      branches_needing_merge_queues << @repository.default_branch if queue_for_default_branch?

      branches_with_merge_queues = begin
        T.let(
          @repository.merge_queues.pluck(:branch).to_set,
          T::Set[String],
        )
      rescue *GitHub::ResilienceMixin::DATABASE_ERROR_TYPES_ALLOWLIST
        # If there are no active merge queue rules, ignore errors loading the
        # existing queues. In this case it is most likely that there is no
        # work to do, and in the worst case leaving a few stale queue records
        # around is better than responding with a 500 error.
        return if branches_needing_merge_queues.empty?
        raise
      end

      to_create = branches_needing_merge_queues - branches_with_merge_queues
      to_destroy = branches_with_merge_queues - branches_needing_merge_queues

      MergeQueue.transaction do
        to_create.each do |branch|
          MergeQueue.create!(repository: @repository, branch:)
        end
        MergeQueue.where(
          repository: @repository,
          branch: to_destroy,
          protected_branch_id: nil,
        ).destroy_all
      end
    end

    sig { params(old_name: String, new_name: String).void }
    def reconcile_default_branch_rename(old_name:, new_name:)
      return unless queue_for_default_branch?
      keep_queue_for_old_name = targeted_branch_names.include?(old_name)

      default_branch_queue = MergeQueue.find_by(
        repository: @repository,
        branch: old_name,
        protected_branch_id: nil,
      )

      MergeQueue.transaction do
        if default_branch_queue
          default_branch_queue.update!(branch: new_name)
        end

        if keep_queue_for_old_name
          MergeQueue.create!(repository: @repository, branch: old_name)
        end
      end
    end

    private

    sig { returns(T::Boolean) }
    def queue_for_default_branch?
      branch_patterns.include?(RuleEngine::Conditions::RefNameTarget::DEFAULT_BRANCH_PATTERN)
    end

    sig { returns(T::Set[String]) }
    memoize def targeted_branch_names
      patterns = branch_patterns
        .reject { RuleEngine::Conditions::RefNameTarget::TRANSLATED_PATTERNS.include?(_1) }

      patterns
        .reject { _1.match?(ProtectedBranch::CONTAINS_WILDCARD) }
        .map { _1.sub("refs/heads/", "") }
        .to_set
    end

    sig { returns(T::Array[String]) }
    memoize def branch_patterns
      refname_conditions.flat_map { _1.parameters["include"] || [] }
    end

    sig { returns(T::Array[RepositoryRuleCondition]) }
    def refname_conditions
      relevant_rulesets.flat_map { _1.conditions.select(&:ref_name?) }
    end

    sig { returns(T::Enumerable[RepositoryRuleset]) }
    def relevant_rulesets
      @repository.rulesets.enabled.targets_branch.includes(:conditions, :rule_configurations)
        .select { _1.rule_configurations.any? { |conf| conf.rule_type == "merge_queue" } }
    end
  end
end
