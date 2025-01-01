# typed: true
# frozen_string_literal: true

class MergeQueues::EntryStatus::ReviewsComponent < ApplicationComponent
  def initialize(merge_state:, base_branch_rule_evaluator:)
    @merge_state = merge_state
    @base_branch_rule_evaluator = base_branch_rule_evaluator
  end

  def call
    render MergeQueues::EntryStatus::DetailComponent.new(
      summary_color: summary_color,
      summary: merge_state.review_policy_decision_reason_summary,
      details: merge_state.review_policy_decision_reason_message,
      test_selector_prefix: "reviews-status",
    )
  end

  private

  attr_reader :merge_state, :base_branch_rule_evaluator

  def render?
    return false unless base_branch_rule_evaluator
    base_branch_rule_evaluator.pull_request_reviews_required? &&
      merge_state.pull_request_review_policy_decision.reason.code != :review_policy_not_required
  end

  def summary_color
    if merge_state.requested_changes?
      :danger
    elsif approval_or_review_required?
      :danger
    else
      :success
    end
  end

  def approval_or_review_required?
    return true if merge_state.blocked_by_review_policy?
    [
      :review_policy_not_satisfied,
      :code_owner_review_required,
      :soc2_approval_process_required
    ].include?(
      merge_state.pull_request_review_policy_decision.reason.code
    )
  end
end
