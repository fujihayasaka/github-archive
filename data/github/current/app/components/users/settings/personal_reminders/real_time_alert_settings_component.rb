# typed: true
# frozen_string_literal: true

class Users::Settings::PersonalReminders::RealTimeAlertSettingsComponent < ApplicationComponent
  EVENT_TYPES = {
    review_request: "Your review is requested",
    team_review_request: "Your team's review is requested",
    review_submission: "Your pull request is approved or has changes requested",
    assignment: "You are assigned",
    comment: "Someone comments on your pull request",
    comment_reply: "Someone comments in a thread you're in",
    mention: "You are mentioned in a comment",
    pull_request_merged: "Your pull request is merged",
    merge_conflict: "Your pull request has merge conflicts",
    check_failure: "Your pull request has failed checks",
  }.freeze

  REAL_TIME_OPTIONS_LABELS = {
    check_failure: "Check names",
  }.freeze

  REAL_TIME_OPTIONS_PLACEHOLDERS = {
    check_failure: "e.g., checkOne,checkTwo",
  }.freeze

  REAL_TIME_OPTIONS_CAPTIONS = {
    check_failure: "Separate with commas",
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

  sig { params(event_type: T.any(String, Symbol)).returns(T::Boolean) }
  def event_type_permits_option?(event_type)
    ReminderEventSubscription::EVENT_TYPES_PERMITTING_OPTIONS.include?(event_type.to_sym)
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
