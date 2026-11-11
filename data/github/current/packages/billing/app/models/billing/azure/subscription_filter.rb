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

    # Azure subscription quota IDs that should not be generally allowed.
    # Customers that wish to use these subscriptions need to be added to the allow list.
    RESTRICTED_QUOTA_IDS = T.let(%w[
      AzurePass_2014-09-01
      MSDN_2014-09-01
      PayAsYouGo_2014-09-01
    ].freeze, T::Array[String])

    sig { params(subscription: T::Hash[Symbol, T.untyped], billable_entity: T.nilable(Billing::Types::Account)).returns(T::Boolean) }
    def self.billable_subscription?(subscription, billable_entity: nil)
      return false if ineligible_quota_id?(subscription[:quota_id])
      return false if restricted_quota_id?(subscription[:quota_id]) &&
        !billable_entity&.feature_flag_enabled?(:billing_azure_subscription_restricted_quota_id_allow_list, default: false)
      true
    end

    sig { params(quota_id: T.nilable(String)).returns(T::Boolean) }
    def self.ineligible_quota_id?(quota_id)
      return false if quota_id.nil?
      INELIGIBLE_QUOTA_IDS.include?(quota_id)
    end

    sig { params(quota_id: T.nilable(String)).returns(T::Boolean) }
    def self.restricted_quota_id?(quota_id)
      return false if quota_id.nil?
      RESTRICTED_QUOTA_IDS.include?(quota_id)
    end
  end
end
