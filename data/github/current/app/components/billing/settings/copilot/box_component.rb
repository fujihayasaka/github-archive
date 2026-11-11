# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    module Copilot
      class BoxComponent < ApplicationComponent
        DATE_FORMAT = "%b %d, %Y".freeze # e.g. May 31, 2022

        attr_reader :copilot_user,
          :eligible_for_free_trial,
          :has_signed_up,
          :qualifies_for_free_usage,
          :subscription_item,
          :update_payment_method_href,
          :product_pricing

        delegate :on_free_trial?,
          :pending_cancellation?,
          :pending_change?,
          :pending_change_identifier,
          :pending_change_interval,
          :pending_product_change_id,
          :pending_item_change_id,
          :product_identifier,
          :in_app_purchase?,
          :apple_in_app_purchase?,
          :google_in_app_purchase?,
          to: :subscription_item, allow_nil: true

        def initialize(subscription_item: nil, eligible_for_free_trial:, qualifies_for_free_usage:, has_signed_up:, copilot_user: nil, update_payment_method_href: nil, product_pricing: nil)
          @subscription_item = subscription_item
          @eligible_for_free_trial = eligible_for_free_trial
          @qualifies_for_free_usage = qualifies_for_free_usage
          @has_signed_up = has_signed_up
          @copilot_user = copilot_user
          @update_payment_method_href = update_payment_method_href
          @product_pricing = product_pricing
        end

        sig { returns(T.nilable(String)) }
        def formatted_price
          return nil unless subscription_item

          if product_pricing&.has_discount?
            product_pricing.discounted_price.format(no_cents_if_whole: false)
          else
            subscription_item.price.format
          end
        end

        sig { returns(T.nilable(String)) }
        def formatted_base_price
          subscription_item&.price&.format
        end

        sig { returns(T::Boolean) }
        def has_coupon_discount?
          product_pricing&.has_discount? || false
        end

        sig { returns(T.nilable(String)) }
        def discount_label
          if percentage_discount?
            "#{discount_percentage}% off"
          else
            "#{formatted_discount_amount} off"
          end
        end

        sig { returns(T.nilable(String)) }
        def formatted_discount_amount
          product_pricing&.discount_amount&.format(no_cents_if_whole: false)
        end

        sig { returns(T::Boolean) }
        def coupon_will_expire?
          product_pricing&.coupon_will_expire? || false
        end

        sig { returns(T.nilable(String)) }
        def coupon_duration_label
          product_pricing&.coupon_duration_label
        end

        sig { returns(T::Boolean) }
        def percentage_discount?
          product_pricing&.percentage_discount? || false
        end

        sig { returns(Integer) }
        def discount_percentage
          product_pricing&.discount_percentage || 0
        end

        memoize def product_name
          if subscription_item
            if on_free_trial?
              return "Copilot Pro (free trial)"
            else
              return subscription_item.name.delete_prefix("GitHub ")
            end
          end

          "Copilot"
        end

        memoize def copilot_provider
          copilot_user&.copilot_provider
        end

        memoize def copilot_provider_name
          copilot_provider&.name
        end

        memoize def has_multiple_copilot_providers?
          copilot_user&.has_multi_access? || false
        end

        memoize def managed_product_name
          copilot_user&.managed_plan_product_name
        end

        memoize def managed_billing_doc_url
          if copilot_user&.has_cfe_access? || copilot_user&.copilot_plan == "enterprise"
            ::Copilot::COPILOT_FOR_ENTERPRISE_DOCUMENTATION
          else
            ::Copilot::COPILOT_FOR_BUSINESS_DOCUMENTATION
          end
        end

        memoize def copilot_pro?
          product_identifier&.product_key == ::Copilot::INDIVIDUAL_PRO_PRODUCT_KEY
        end

        memoize def copilot_pro_plus?
          product_identifier&.product_key == ::Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
        end

        memoize def copilot_max?
          product_identifier&.product_key == ::Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
        end

        memoize def has_pro_access?
          copilot_user&.has_pro_access? || false
        end

        memoize def has_pro_plus_access?
          copilot_user&.has_pro_plus_access? || false
        end

        memoize def has_educational_access?
          copilot_user&.has_educational_access? || false
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

        def pending_downgrade_to_pro?
          return false unless copilot_pro_plus? || copilot_max?
          pending_change? && pending_change_identifier.product_key == ::Copilot::INDIVIDUAL_PRO_PRODUCT_KEY
        end

        def pending_downgrade_to_pro_plus?
          return false unless copilot_max?
          pending_change? && pending_change_identifier.product_key == ::Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
        end

        def pending_downgrade_product_name
          if pending_downgrade_to_pro?
            ::Copilot.individual_pro_product_name
          elsif pending_downgrade_to_pro_plus?
            ::Copilot.individual_pro_plus_product_name
          else
            "N/A"
          end
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
          return false unless subscription_item.present? && !on_free_trial?
          edu_identifier = copilot_user&.copilot_edu_product_identifier

          return false if edu_identifier.present? && subscription_item.product_identifier == edu_identifier
          true
        end

        def can_change_billing_plan?
          # We want to also make sure the subscription is not managed by Apple or Google.
          # In those cases, we cannot let the user change the subscription within GitHub, they need
          # to manage it within the respective app store it was purchased in.
          (on_free_trial? || !pending_change?) && !in_app_purchase?
        end

        def remove_annual_plan_undo?
          return false unless copilot_user

          FeatureFlag.vexi.enabled?(:copilot_remove_annual_plan_undo, copilot_user.user_object, default: false)
        end

        def annual_plan_copy_updated?
          return false unless copilot_user

          FeatureFlag.vexi.enabled?(:copilot_annual_plan_copy_updated, copilot_user.user_object, default: false)
        end

        def all_copilot_subscriptions_cancelled?
          Billing::Public::SubscriptionItem.all_subscriptions_cancelled?(
            product_type: ::Copilot::PRODUCT_TYPE,
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

        def can_cancel_and_refund_immediately?
          current_user.feature_flag_enabled?(:copilot_cancel_and_refund_subscription, default: false) ||
            (current_user.feature_flag_enabled?(:copilot_yearly_cancel_and_refund, default: false) && on_yearly_plan? && pending_cancellation?) # We want to continue to allow users with yearly to continue to have this even after we stop it for non cancelled
        end

        def meets_trust_tier_requirements_for_max?
          copilot_user&.meets_trust_tier_requirements_for_max? != false
        end
      end
    end
  end
end
