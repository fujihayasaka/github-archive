# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestRepoState < MergeConditions::BaseMergeCondition
  FAILED_MESSAGE = "Pull request cannot be merged because repository is not in a writable state."

  def display_name
    "Pull request repository state"
  end

  def description
    "The repository must be not archived or locked"
  end

  def message
    result == :passed ? nil : FAILED_MESSAGE
  end

  def async_condition
    pull_request.async_base_repository.then do |base_repository|
      if !base_repository.writable?
        evaluation_result.errors << "Base repository is not writable."
      end
    end
  end
end
