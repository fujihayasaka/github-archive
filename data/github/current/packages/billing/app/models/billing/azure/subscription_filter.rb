# typed: strict
# frozen_string_literal: true

module Billing::Azure
  # Provides filtering for Azure subscriptions to exclude those that are ineligible for billing purposes.
  module SubscriptionFilter
    extend T::Helpers

    # Azure subscription quota IDs for free/educational subscriptions
    # These are not eligible for billing purposes
    INELIGIBLE_QUOTA_IDS = T.let(%w[
      FreeTrial_2014-09-01
      AzureForStudents_2018-01-01
      DreamSpark_2015-02-01
    ].freeze, T::Array[String])

    sig { params(subscription: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
    def self.billable_subscription?(subscription)
      return true unless FeatureFlag.vexi.enabled?(:billing_filter_azure_subscriptions_by_quota_id, default: false)
      return false if ineligible_quota_id?(subscription[:quota_id])
      true
    end

    sig { params(quota_id: T.nilable(String)).returns(T::Boolean) }
    def self.ineligible_quota_id?(quota_id)
      return false if quota_id.nil?
      INELIGIBLE_QUOTA_IDS.include?(quota_id)
    end
  end
end
