# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

module Reminders
  module CiFailed
    EVENT_TYPE = :check_failure

    def ci_failed_events(pull_requests, target)
      pull_requests.map do |pull_request|
        organization = pull_request.repository.organization
        next if organization.nil?

        reminders = reminders_for_pull_request(organization, pull_request, target)

        reminders.map do |reminder|
          Reminders::RealTimeEvent.new(
            actor: pull_request.user,
            context: {
              status: status_params(target),
            },
            type: EVENT_TYPE,
            pull_request_ids: [pull_request.id],
            reminder: reminder,
            repository_id: pull_request.repository_id,
          )
        end
      end.flatten.compact
    end

    def reminders_for_pull_request(organization, pull_request, target)
      reminders = PersonalReminder
        .includes(:event_subscriptions)
        .for_remindable(organization)
        .where(user_id: pull_request.user_id)
        .for_event_type(EVENT_TYPE)

      reminders.select do |reminder|
        failed_check_subscription = reminder.subscription_for_type(EVENT_TYPE)
        failed_check_subscription.options_includes?(target_name(target))
      end
    end

    def status_params(target)
      {
        target_url: target_url(target),
        name: target_name(target),
      }
    end
  end
end
