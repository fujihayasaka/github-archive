# typed: true
# frozen_string_literal: true

module Issue::StateReasonDependency
  extend ActiveSupport::Concern

  OCTICONS = {
    not_planned: {
      icon: "skip",
      class: "color-fg-muted",
      title: "Closed as not planned",
      aria_label: "Closed as not planned issue",
    },
    duplicate: {
      icon: "skip",
      class: "color-fg-muted",
      title: "Closed as duplicate",
      aria_label: "Closed as duplicate issue",
    }
  }.freeze

  Values = {
    not_planned: 1,
    reopened: 2,
    duplicate: 3,
  }.freeze

  included do
    T.bind(self, T.class_of(ApplicationRecord::Base))
    enum :state_reason, Values, prefix: true
  end

  IssueStateTransition = Struct.new(:old_state, :old_reason, :new_state, :new_reason) do
    def validates?(other)
      ok = old_state == other.old_state && new_state == other.new_state

      if old_reason.is_a?(Array)
        ok &&= old_reason.include?(other.old_reason&.to_sym)
      else
        ok &&= old_reason == other.old_reason&.to_sym
      end

      if new_reason.is_a?(Array)
        ok &&= new_reason.include?(other.new_reason&.to_sym)
      else
        ok &&= new_reason == other.new_reason&.to_sym
      end
    end
  end

  # We did not add COMPLETED as a state_reason to avoid updating all the closed issues to state_reason=Completed
  # and to provide backwards compatibility.
  # We are however using it here to make the transitions more explicit.
  COMPLETED = nil
  PermittedTransitions = [
    IssueStateTransition.new("open", [nil, :reopened, :not_planned, :duplicate], "closed", [COMPLETED, :not_planned, :duplicate]),
    IssueStateTransition.new("closed", COMPLETED, "open", nil),
    IssueStateTransition.new("closed", [:not_planned, :duplicate, COMPLETED], "open", :reopened),
    IssueStateTransition.new("closed", COMPLETED, "closed", [:not_planned, :duplicate]),
    IssueStateTransition.new("closed", :not_planned, "closed", [:duplicate, COMPLETED]),
    IssueStateTransition.new("closed", :duplicate, "closed", [:not_planned, COMPLETED]),
  ].freeze

  # Public: Is the state transition valid?
  # Permitted state transitions are described by PermittedTransitions
  def state_transition_valid?
    T.bind(self, Issue)

    return true if state.nil?
    return true if pull_request?

    allowed_transitions = PermittedTransitions
    old_reason = state_reason_was
    reason = state_reason

    wanted = IssueStateTransition.new(state_was, old_reason, state, reason)
    valid = T.let(false, T::Boolean)
    allowed_transitions.each do |transition|
      valid ||= (transition.validates?(wanted))
    end

    errors.add(:state_reason, "Cannot transition to this state") unless valid
    valid
  end

  def state_or_state_reason_changed?
    T.bind(self, Issue)
    state_changed? || state_reason_changed?
  end
end
