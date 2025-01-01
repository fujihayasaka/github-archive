# typed: strict
# frozen_string_literal: true

# Components that inherit from this class have test coverage
# instead, since no view is associated with `BaseComponent`.
# rubocop:disable ViewComponent/ComponentsHaveUnitTests
class Closables::BaseComponent < ApplicationComponent
  # Issues store the completed `state_reason` as `nil`. So we have
  # to use the actual reason value for our form.
  ISSUE_STATE_REASON_FALLBACK = "completed"

  Closable = T.type_alias do
    T.any(
      Issue,
      Discussion,
      # We use this for issue timelines that had GraphQL removed from the view
      Issue::Adapter::CrossReferenceSourceIssueAdapter,
    )
  end

  class Reason < T::Struct
    prop :title, String
    prop :description, String
    prop :value, String
    prop :octicon, Symbol
    prop :octicon_color, Symbol
    prop :badge_scheme, Symbol
    prop :badge_title, String
  end

  ISSUE_REASONS = T.let([
    Reason.new(
      title: "Close as completed",
      description: "Done, closed, fixed, resolved",
      value: "completed",
      octicon: :"issue-closed",
      octicon_color: :done,
      badge_scheme: :merged,
      badge_title: "Closed",
    ),
    Reason.new(
      title: "Close as not planned",
      description: "Won't fix, can't repro, duplicate, stale",
      value: "not_planned",
      octicon: Issue::StateReasonDependency::OCTICONS[:not_planned][:icon].to_sym,
      octicon_color: :muted,
      badge_scheme: :default,
      badge_title: Issue::StateReasonDependency::OCTICONS[:not_planned][:title],
    ),
  ], T::Array[Reason])

  DISCUSSION_REASONS = T.let([
    Reason.new(
      title: "Close as #{Discussion::StateReasonable::CloseReason::Resolved.serialize}",
      description: Discussion::StateReasonable::CloseReason::Resolved.description,
      value: Discussion::StateReasonable::CloseReason::Resolved.serialize,
      octicon: :"discussion-closed",
      octicon_color: :done,
      badge_scheme: :merged,
      badge_title: "Closed as #{Discussion::StateReasonable::CloseReason::Resolved.serialize}",
    ),
    Reason.new(
      title: "Close as #{Discussion::StateReasonable::CloseReason::Outdated.serialize}",
      description: Discussion::StateReasonable::CloseReason::Outdated.description,
      value: Discussion::StateReasonable::CloseReason::Outdated.serialize,
      octicon: :"discussion-outdated",
      octicon_color: :muted,
      badge_scheme: :default,
      badge_title: "Closed as #{Discussion::StateReasonable::CloseReason::Outdated.serialize}",
    ),
    Reason.new(
      title: "Close as #{Discussion::StateReasonable::CloseReason::Duplicate.serialize}",
      description: Discussion::StateReasonable::CloseReason::Duplicate.description,
      value: Discussion::StateReasonable::CloseReason::Duplicate.serialize,
      octicon: :"discussion-duplicate",
      octicon_color: :muted,
      badge_scheme: :default,
      badge_title: "Closed as #{Discussion::StateReasonable::CloseReason::Duplicate.serialize}",
    ),
  ], T::Array[Reason])

  sig { params(closable: Closable).void }
  def initialize(closable:)
    @closable = closable
  end

  private

  sig { returns(Closable) }
  attr_reader :closable

  sig { returns(T::Array[Reason]) }
  memoize def options
    closable.is_a?(Discussion) ? DISCUSSION_REASONS : ISSUE_REASONS
  end

  sig { returns(T.nilable(Reason)) }
  memoize def current_reason
    return unless closable.closed?
    state_reason = closable.state_reason&.downcase || ISSUE_STATE_REASON_FALLBACK
    # make sure new duplicate state reason for issues isn't rendered in Rails
    state_reason = "not_planned" if !closable.is_a?(Discussion) && state_reason == "duplicate"
    T.must(options.find { |option| option.value == state_reason })
  end
end
