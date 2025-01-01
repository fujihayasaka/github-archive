# typed: true
# frozen_string_literal: true

# Class to encapsulate logic to check whether a pull request's head branch
# can be updated with changes from the base branch.
class PullRequest::Updateability
  class Success
    def success?
      true
    end
  end

  class Failure
    def initialize(failure_reason)
      @failure_reason = failure_reason
    end

    attr_reader :failure_reason

    def success?
      false
    end
  end

  def initialize(pull_request)
    @pull_request = pull_request
  end

  # Public: Check if a pull request can be updated through a merge.
  #
  # Returns either a Success or a Failure object.
  def check_mergeability(user)
    unless pull_request.head_ref_pushable_by?(user)
      return failure("You don’t have write access to #{pull_request.head_label}.")
    end

    unless pull_request.behind_base?
      return failure("This branch is up to date.")
    end

    unless pull_request.git_merges_cleanly?(enqueue: false)
      return failure("This branch has conflicts with the base branch.")
    end
    success
  end

  def check_required_linear_history
    if pull_request.repository&.feature_enabled?(:linear_history_check_consider_missing_head_success)
      if pull_request.head_repository && pull_request.head_branch_rule_evaluator&.required_linear_history_enabled?
        failure("The branch #{pull_request.head_label} must have linear history.")
      else
        success
      end
    else
      if pull_request.head_branch_rule_evaluator&.required_linear_history_enabled?
        failure("The branch #{pull_request.head_label} must have linear history.")
      else
        success
      end
    end
  end

  def check_rebaseability(user)
    mergeability_check = check_mergeability(user)
    return mergeability_check unless mergeability_check.success?

    unless pull_request.rebase_safe?
      return failure("This branch has rebase conflicts with the base branch")
    end

    success
  end

  private

  attr_reader :pull_request

  def failure(reason)
    Failure.new(reason)
  end

  def success
    Success.new
  end
end
