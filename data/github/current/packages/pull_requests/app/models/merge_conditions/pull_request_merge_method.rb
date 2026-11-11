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
    case @merge_method
    when :merge
      @pull_request.async_merge_commit_allowed?(actor: user).then do |allowed|
        evaluation_result.errors << "Merge is not an allowed merge method in this repository." unless allowed
      end
    when :rebase
      @pull_request.async_rebase_merge_allowed?(actor: user).then do |allowed|
        evaluation_result.errors << "Rebase is not an allowed merge method in this repository." unless allowed
      end
    when :squash
      @pull_request.async_squash_merge_allowed?(actor: user).then do |allowed|
        evaluation_result.errors << "Squash is not an allowed merge method in this repository." unless allowed
      end
    end
  end
end
