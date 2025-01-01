# typed: true
# frozen_string_literal: true

# This module implements methods expected by web and email notifications.
module GateRequest::NotificationsAdapter
  extend T::Helpers

  requires_ancestor { GateRequest }

  delegate :workflow_run, to: :check_suite
  delegate :async_notifications_list,
    :notifications_list,
    :notifications_thread,
    :notifications_author,
    :permalink,
    :repository,
    to: :workflow_run

  alias :user :notifications_author

  def user_id
    user.id
  end

  def body
    "[#{repository.name_with_display_owner}] #{workflow_run.name}: Your review was requested to deploy"
  end

  def message_id
    permalink(include_host: false) + "/request/#{id}"
  end
  alias :notification_id :message_id

  # Overrides for Summarizable#get_notification_summary
  def get_notification_summary
    list = Newsies::List.to_object(notifications_list)
    thread = Newsies::List.to_object(notifications_thread)
    GitHub.newsies.web.find_rollup_summary_by_thread(list, thread)
  end
end
