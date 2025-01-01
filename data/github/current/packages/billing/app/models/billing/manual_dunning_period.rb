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
      destroy
    end

    # Days spent within the dunning period
    # e.g if started 2 days ago, then return 2
    sig { returns(Integer) }
    def days_in_dunning_period
      (Date.current - created_at.to_date).to_i
    end

    sig { returns(Time) }
    def due_date
      (created_at + 13.days).in_time_zone
    end

    private

    sig { params(event: T.any(Symbol, String)).void }
    def instrument_event(event)
      GitHub.dogstats.increment "manual_dunning_period.#{event}",
        tags: ["attempts:#{notification_attempts}", "business_account:#{billable_business?}"]

      if event == "notify"
        notification_payload = {
          attempt: notification_attempts,
        }
        if billable_business?
          notification_payload[:business] = billable_entity
        else
          notification_payload[:user] = billable_entity
        end

        GitHub.instrument("billing.send_manual_dunning_notification", notification_payload)
      end
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
      days_in_dunning_period >= 7 && notification_attempts == 1
    end

    sig { returns(T::Boolean) }
    def final_notification?
      !!(notification_attempts == 2 && days_in_dunning_period >= 14)
    end

    sig { void }
    def send_notifications
      update_global_notice
      BillingNotificationsMailer.manual_dunning_attempts(
        billable_entity,
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
