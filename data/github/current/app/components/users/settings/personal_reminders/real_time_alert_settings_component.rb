# typed: true
# frozen_string_literal: true

class Users::Settings::PersonalReminders::RealTimeAlertSettingsComponent < ApplicationComponent
  EVENT_TYPES = {
  review_request: "Your pull request review is requested",
    team_review_request: "Your team's pull request review is requested",
    review_submission: "Your pull request is approved or has changes requested",
    assignment: "You are assigned to a pull request",
    comment: "Someone comments on your pull request",
    comment_reply: "Someone comments in a thread you're in on a pull request",
    mention: "You are mentioned in a comment on a pull request",
    pull_request_merged: "Your pull request is merged",
    merge_conflict: "Your pull request has merge conflicts",
    check_failure: "Your pull request has failed checks",
  }.freeze

  REAL_TIME_OPTIONS_LABELS = {
    check_failure: "Check names",
    team_review_request: "Teams",
  }.freeze

  REAL_TIME_OPTIONS_PLACEHOLDERS = {
    check_failure: "e.g., checkOne,checkTwo",
    team_review_request: "e.g., frontend-team,backend-team",
  }.freeze

  REAL_TIME_OPTIONS_CAPTIONS = {
    check_failure: "Separate with commas",
    team_review_request: "Leave blank for all teams, or enter comma-separated team slugs (maximum 5 teams)",
  }.freeze

  sig { params(form: ActionView::Helpers::FormBuilder, personal_reminder: PersonalReminder).void }
  def initialize(form:, personal_reminder:)
    @form = form
    @personal_reminder = personal_reminder
  end

  private

  sig { returns ActionView::Helpers::FormBuilder }
  attr_reader :form

  sig { returns PersonalReminder }
  attr_reader :personal_reminder

  def selected_event_types
    if personal_reminder.subscribed_to_events?
      personal_reminder.event_types
    else
      %w[review_request team_review_request review_submission]
    end
  end

  def event_types_filtered
    if personal_reminder.merge_conflict_sunset?
      EVENT_TYPES.except(:merge_conflict)
    else
      EVENT_TYPES
    end
  end

  sig { params(event_type: T.any(String, Symbol)).returns(T::Boolean) }
  def event_type_permits_option?(event_type)
    event_type_sym = event_type.to_sym

    # Skip team_review_request if feature flag is disabled
    if event_type_sym == :team_review_request
      return false unless FeatureFlag.vexi.enabled?(:team_review_request_team_filtering, personal_reminder.user, default: false)
    end

    ReminderEventSubscription::EVENT_TYPES_PERMITTING_OPTIONS.include?(event_type_sym)
  end

  sig { params(event_type: T.any(String, Symbol)).returns(T::Boolean) }
  def real_time_selected?(event_type)
    personal_reminder.event_types.include?(event_type)
  end

  sig { params(event_type: T.any(String, Symbol)).returns(String) }
  def real_time_options_label(event_type)
    REAL_TIME_OPTIONS_LABELS[event_type.to_sym] || "Event type #{event_type} options"
  end

  sig { params(event_type: T.any(String, Symbol)).returns(T.nilable(String)) }
  def real_time_options_caption(event_type)
    REAL_TIME_OPTIONS_CAPTIONS[event_type.to_sym]
  end

  sig { params(event_type: T.any(String, Symbol)).returns(T.nilable(String)) }
  def real_time_options_placeholder(event_type)
    REAL_TIME_OPTIONS_PLACEHOLDERS[event_type.to_sym]
  end

  sig { params(event_type: T.any(String, Symbol)).returns(T.untyped) }
  def real_time_options(event_type)
    event_subscription = event_subscriptions.detect { |sub| sub.event_type == event_type.to_s }
    event_subscription&.options
  end

  memoize def event_subscriptions
    personal_reminder.event_subscriptions
  end
end
