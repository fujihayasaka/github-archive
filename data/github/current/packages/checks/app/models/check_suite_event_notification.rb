# typed: true
# frozen_string_literal: true

class CheckSuiteEventNotification
  include GlobalID::Identification
  attr_reader :check_suite

  delegate :async_notifications_list,
    :conclusion,
    :creator,
    :creator_id,
    :global_relay_id,
    :head_branch,
    :notifications_list,
    :notifications_thread,
    :permalink,
    :permissions_wrapper,
    :push,
    :repository,
    :created_at,
    :updated_at,
    to: :check_suite

  # Public: Find the CheckSuite for the given id and wrap it with
  # CheckSuiteEventNotification.
  #
  # We want to distinguish between a CheckSuite with one completion status from
  # the same CheckSuite with a different completion status, so the id value
  # we will pass consists of the CheckSuite id and some timestamp to ensure
  # uniqueness.
  #
  # id - The CheckSuite primary key id + timestamp.
  #
  # Returns a CheckSuiteEventNotification or nil when no CheckSuiteEvent exists
  # for the id.
  #
  # rubocop:disable GitHub/FindByDef
  def self.find_by_id(id)
    check_suite_id, _timestamp = id.split(";")

    if check_suite = CheckSuite.find_by(id: check_suite_id)
      new(check_suite)
    end
  end

  def self.find(id)
    find_by_id(id)
  end

  def initialize(check_suite)
    @check_suite = check_suite
  end

  def deliver?(settings)
    return false if check_suite.action_required?
    settings.continuous_integration_all_results? ||
      (settings.continuous_integration_failures_only? && check_suite.failed?)
  end

  # Build an ID that's unique to the update
  def id
    [check_suite.id, updated_at.to_i].join(";")
  end

  def body
    "The run for #{head_branch} #{conclusion_as_phrase}."
  end
  alias body_html body

  # For Newsies::Emails::CheckSuiteEventNotification message construction
  # Unique identifier for this check suite update
  def message_id
    "<#{repository.name_with_display_owner}/check-suites/#{global_relay_id}/#{updated_at.to_i}@#{GitHub.urls.host_name}>"
  end

  # The sender of the notification (must be a `User`) - in this case, the
  # creator of the check suite because they triggered the run. See
  # `Newsies::Emails::Message` for usage.
  def notifications_author
    user
  end

  # This is used in web notifications to indicate who triggered the event.
  # See NotificationSummary#summarize_comment for more information.
  def user
    creator
  end

  def user_id
    creator_id
  end

  def check_suite_conclusion
    check_suite.conclusion
  end

  # Overrides for Summarizable#get_notification_summary
  def get_notification_summary
    list = Newsies::List.to_object(notifications_list)
    thread = Newsies::List.to_object(notifications_thread)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end

  private

  def conclusion_as_phrase
    case conclusion
    when "success"
      "has succeeded"
    when "failure"
      "has failed"
    when "cancelled"
      "was cancelled"
    when "action_required"
      "requires action"
    when "skipped"
      "was skipped"
    when "timed_out"
      "timed out"
    else
      "has completed"
    end
  end
end
