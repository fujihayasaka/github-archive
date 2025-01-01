# typed: true
# frozen_string_literal: true

class MergeConditions::PullRequestState < MergeConditions::BaseMergeCondition
  FAILED_MESSAGE = "Pull request must be open and not in draft mode in order to be merged."

  def display_name
    "Pull request state"
  end

  def description
    "Pull request must be open and not in draft mode in order to be merged"
  end

  def message
    result == :passed ? nil : FAILED_MESSAGE
  end

  def async_condition
    pull_request.async_in_merge_queue?.then do |in_merge_queue|
      if in_merge_queue
        evaluation_result.errors << "Pull request is in merge queue."
      end

      if !pull_request.open?
        evaluation_result.errors << "Pull request is not open."
      end

      if pull_request.draft?
        evaluation_result.errors << "Pull request is in draft."
      end
    end
  end
end
