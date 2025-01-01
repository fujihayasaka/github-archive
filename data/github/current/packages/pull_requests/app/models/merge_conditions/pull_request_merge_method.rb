# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestMergeMethod < MergeConditions::BaseMergeCondition
  def display_name
    "Pull request merge method"
  end

  def description
    "The selected merge method must be valid for the base repository."
  end

  def message
    evaluation_result.errors.first
  end

  def async_condition
    @pull_request.async_base_repository.then do |base_repo|
      case @merge_method
      when :merge
        Promise.all([
          base_repo.async_merge_commit_allowed?,
          @pull_request.async_batch_base_branch_rule_evaluator
        ]).then do |allowed, base_branch_rule_evaluator|
          if !allowed
            evaluation_result.errors << "Merge is not an allowed merge method in this repository."
          elsif base_branch_rule_evaluator&.required_linear_history_enabled?
            evaluation_result.errors << "The base branch does not accept merge commits."
          end
        end
      when :rebase
        base_repo.async_rebase_merge_allowed?.then do |allowed|
          evaluation_result.errors << "Rebase is not an allowed merge method in this repository." unless allowed
        end
      when :squash
        base_repo.async_squash_merge_allowed?.then do |allowed|
          evaluation_result.errors << "Squash is not an allowed merge method in this repository." unless allowed
        end
      end
    end
  end
end
