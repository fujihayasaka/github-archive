# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Copilot
      class BoxComponent < ApplicationComponent
        DATE_FORMAT = "%b %d, %Y".freeze # e.g. May 31, 2022

        attr_reader :copilot_organization,
          :copilot_user,
          :eligible_for_free_trial,
          :has_signed_up,
          :qualifies_for_free_usage,
          :subscription_item,
          :update_payment_method_href

        delegate :on_free_trial?,
          :pending_cancellation?,
          :pending_change?,
          :pending_change_interval,
          :pending_product_change_id,
          :pending_item_change_id,
          :in_app_purchase?,
          :apple_in_app_purchase?,
          :google_in_app_purchase?,
          to: :subscription_item, allow_nil: true

        def initialize(subscription_item:, eligible_for_free_trial:, qualifies_for_free_usage:, has_signed_up:, copilot_organization: nil, copilot_user: nil, update_payment_method_href: nil)
          @subscription_item = subscription_item
          @eligible_for_free_trial = eligible_for_free_trial
          @qualifies_for_free_usage = qualifies_for_free_usage
          @has_signed_up = has_signed_up
          @copilot_organization = copilot_organization
          @copilot_user = copilot_user
          @update_payment_method_href = update_payment_method_href
        end

        memoize def product_name
          if copilot_organization
            if copilot_organization.copilot_plan_enterprise? || copilot_organization.on_free_copilot_enterprise_trial?
              return "GitHub #{::Copilot::ENTERPRISE_PRODUCT_NAME}"
            else
              return "GitHub #{::Copilot::BUSINESS_PRODUCT_NAME}"
            end
          end

          return "GitHub Copilot trial" if on_free_trial?
          return "GitHub Copilot Pro" if copilot_user

          "GitHub Copilot"
        end

        def on_monthly_plan?
          subscription_item&.monthly?
        end

        def on_yearly_plan?
          subscription_item&.yearly?
        end

        # If the user has time left in their free trial but opted to schedule a cancellation return true
        def pending_trial_cancellation?
          on_free_trial? && pending_cancellation?
        end

        def pending_subscription_cancellation?
          !on_free_trial? && pending_cancellation?
        end

        def free_trial_ends_on
          return "N/A" unless subscription_item&.free_trial_ends_on

          subscription_item.free_trial_ends_on.strftime(DATE_FORMAT)
        end

        def subscription_ends_on
          return "N/A" unless subscription_item&.ends_on

          subscription_item.ends_on.strftime(DATE_FORMAT)
        end

        def next_billing_date
          return "N/A" unless subscription_item&.next_billing_date

          subscription_item.next_billing_date.strftime(DATE_FORMAT)
        end

        def paid_subscriber?
          subscription_item.present? && !on_free_trial?
        end

        def can_change_billing_plan?
          # We want to also make sure the subscription is not managed by Apple or Google.
          # In those cases, we cannot let the user change the subscription within GitHub, they need
          # to manage it within the respective app store it was purchased in.
          (on_free_trial? || !pending_change?) && !in_app_purchase?
        end

        def all_copilot_subscriptions_cancelled?
          Billing::Public::SubscriptionItem.all_subscriptions_cancelled?(
            product_type: Billing::ProductUUID::COPILOT_PRODUCT_TYPE,
            account: copilot_user.user_object
          )
        end

        def can_request_copilot?
          return false if GitHub.enterprise?
          return false unless copilot_user

          (pending_cancellation? || all_copilot_subscriptions_cancelled?) &&
            copilot_user.organizations.any? do |organization|
              MemberFeatureRequest.can_request?(
                copilot_user.user_object,
                organization,
                MemberFeatureRequest::Feature::CopilotForBusiness
              )
            end
        end

        def billing_date_text
          if pending_trial_cancellation?
            "Access expires"
          elsif on_free_trial?
            "Free until"
          else
            "Next payment"
          end
        end

        def in_app_purchase_store_url
          return nil unless subscription_item

          if apple_in_app_purchase?
            helpers.apple_app_store_subscriptions_url
          elsif google_in_app_purchase?
            helpers.google_app_store_subscriptions_url
          end
        end
      end
    end
  end
end
