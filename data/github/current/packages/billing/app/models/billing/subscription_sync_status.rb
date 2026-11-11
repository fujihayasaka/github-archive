# typed: strict
# frozen_string_literal: true

module Billing
  class SubscriptionSyncStatus < ApplicationRecord::Domain::Billing

    RECENCY_THRESHOLD = T.let(5.minutes, ActiveSupport::Duration)

    scope :unsuccessful, -> { where(external_sync_status: Billing::SubscriptionSyncStatus.external_sync_statuses.values - %w[declined success suspended]) }
    scope :ignoring_recent, -> { where("updated_at < ?", RECENCY_THRESHOLD.ago) }

    belongs_to :target, polymorphic: true
    belongs_to :plan_subscription

    enum :external_sync_status, {
      declined: "declined",
      failed_but_retrying: "failed_but_retrying",
      failure: "failure",
      pending: "pending",
      success: "success",
      suspended: "suspended",
      under_investigation: "under_investigation",
    }
    scope :not_suspended, -> { where.not(external_sync_status: :suspended) }
    scope :not_under_investigation, -> { where.not(external_sync_status: :under_investigation) }

    validates :target, presence: true
    validates :plan_subscription, presence: true
    validates :investigation_notes, length: { maximum: 255 }

    sig { returns(T::Boolean) }
    def succeed!
      update(external_sync_status: :success)
    end

    sig { returns(T::Boolean) }
    def fail!
      update(external_sync_status: :failure)
    end

    sig { returns(String) }
    def zuora_subscription_url
      if zuora_subscription_id = plan_subscription&.zuora_subscription_id
        "#{GitHub.zuora_host}/apps/Subscription.do?method=view&id=#{zuora_subscription_id}"
      else
        ""
      end
    end

    sig { returns(T::Boolean) }
    def on_last_retry?
      external_sync_status == "failed_but_retrying" && number_of_retries_remaining <= 1
    end
  end
end
