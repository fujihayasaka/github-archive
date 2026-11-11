# typed: strict
# frozen_string_literal: true

module Billing
  class ManualDunningPeriod < ApplicationRecord::Domain::Billing

    include Instrumentation::Model

    # A ManualDunningPeriod may apply to a User, Organization, or a Business.
    # Use #billable_entity to refer to either the User/Organization/Business.
    # - If this is for a User or Organization, user_id will be present.
    # - If this is for a Business, customer_id for the Customer for the
    #   Business will be present.
    belongs_to :user
    belongs_to :customer

    delegate :business, to: :customer, allow_nil: true

    ONE_DAY_IN_HOURS = 24

    sig { returns(Billing::Types::Account) }
    def billable_entity
      billable_user? ? user : business
    end

    sig { returns(T::Boolean) }
    def billable_user?
      user.present?
    end

    sig { returns(T::Boolean) }
    def billable_business?
      !billable_user? && business.present?
    end

    scope :created_before, -> (date) { where(created_at: ..date) }

    # Track the dunning timeline
    sig { returns(T.nilable(T.self_type)) }
    def run
      return destroy unless billable_entity.present?
      return destroy unless billable_entity.autopay_disabled_by_india_rbi?
      return destroy if billable_entity.balance.zero?

      if valid_notification_attempt?
        send_notifications
        increment!(:notification_attempts)
        instrument_event("notify")
      end

      if notification_attempts == 3
        billable_entity.set_billing_attempts(notification_attempts)

        ::Billing::DunSubscription.perform billable_entity,
          skip_notification: true

        destroy
      end
    end

    sig { void }
    def process_payment!
      instrument_event("paid")
      GitHub.dogstats.distribution("billing.manual_dunning_period.days_to_payment", days_in_dunning_period,
        tags: ["attempts:#{notification_attempts}", "business_account:#{billable_business?}", "shorter_due_date:#{use_shorter_due_date?}"])
      destroy
    end

    # Days spent within the dunning period
    # e.g if started 2 days ago, then return 2
    sig { returns(Integer) }
    def days_in_dunning_period
      (Date.current - created_at.to_date).to_i
    end

    sig { returns(Integer) }
    def hours_in_dunning_period
      ((Time.current.in_time_zone - created_at.in_time_zone) / 1.hour).to_i
    end

    sig { returns(Time) }
    def due_date
      return (created_at + 1.day).in_time_zone if use_shorter_due_date?
      (created_at + 13.days).in_time_zone
    end

    private

    sig { params(event: T.any(Symbol, String)).void }
    def instrument_event(event)
      GitHub.dogstats.increment "manual_dunning_period.#{event}",
        tags: ["attempts:#{notification_attempts}", "business_account:#{billable_business?}", "shorter_due_date:#{use_shorter_due_date?}"]

      if event == "notify"
        notification_payload = {
          attempt: notification_attempts,
          shorter_due_date: use_shorter_due_date?,
        }
        if billable_business?
          notification_payload[:business] = billable_entity
        else
          notification_payload[:user] = billable_entity
        end

        GitHub.instrument("billing.send_manual_dunning_notification", notification_payload)
      end
    end

    # This is to reduce the amount of time bad actors can abuse the manual payment system by accumulating usage without paying for it
    sig { returns(T::Boolean) }
    def use_shorter_due_date?
      billable_entity.feature_flag_enabled?(:billing_shorter_manual_dunning_due_date, default: false) && billable_entity.never_successfully_billed?
    end

    sig { returns(T::Boolean) }
    def valid_notification_attempt?
      first_notification? || second_notification? || final_notification?
    end

    sig { returns(T::Boolean) }
    def first_notification?
      notification_attempts.to_i.zero?
    end

    sig { returns(T::Boolean) }
    def second_notification?
      return hours_in_dunning_period >= ONE_DAY_IN_HOURS && notification_attempts == 1 if use_shorter_due_date?
      hours_in_dunning_period >= (7 * ONE_DAY_IN_HOURS) && notification_attempts == 1
    end

    sig { returns(T::Boolean) }
    def final_notification?
      return hours_in_dunning_period >= (2 * ONE_DAY_IN_HOURS) && notification_attempts == 2 if use_shorter_due_date?
      !!(notification_attempts == 2 && hours_in_dunning_period >= (14 * ONE_DAY_IN_HOURS))
    end

    sig { void }
    def send_notifications
      update_global_notice
      BillingNotificationsMailer.manual_dunning_attempts(
        billable_entity,
        self,
        notification_attempts
      ).deliver_later
    end

    sig { void }
    def update_global_notice
      if billable_entity.is_a?(Business)
        Billing::BusinessManualDunningCheckJob.perform_later billable_entity
      elsif billable_entity.organization?
        Billing::OrgManualDunningCheckJob.perform_later billable_entity
      else
        Billing::PersonalManualDunningCheckJob.perform_later billable_entity
      end
    end
  end
end
