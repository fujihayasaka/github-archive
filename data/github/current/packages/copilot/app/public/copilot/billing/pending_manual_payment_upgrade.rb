# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    # Builds the Billing::PendingManualPaymentUpgrade that finalizes a deferred Copilot individual
    # upgrade (Pro / Pro+ / Max) after a successful manual (India RBI) payment. The Copilot signup
    # controllers pass the result to Billing::ManualPaymentRedirect#redirect_to_manual_payment_if_required
    # so the generic manual payments page can re-POST the original signup request once the payment
    # is confirmed. Returns nil (opting out) when the feature is disabled or the product is not a
    # supported individual upgrade.
    class PendingManualPaymentUpgrade
      # Feature flag gating the synchronous manual-payment upgrade finalization for Copilot.
      FEATURE_FLAG = :copilot_rbi_manual_payment_signup

      sig { params(user: ::User, product_key: String).returns(T.nilable(::Billing::PendingManualPaymentUpgrade)) }
      def self.build(user:, product_key:)
        return nil unless FeatureFlag.vexi.enabled?(FEATURE_FLAG, user, default: false)

        new(user).for_product(product_key)
      end

      sig { params(user: ::User).void }
      def initialize(user)
        @user = user
      end

      sig { params(product_key: String).returns(T.nilable(::Billing::PendingManualPaymentUpgrade)) }
      def for_product(product_key)
        routes = Rails.application.routes.url_helpers

        case product_key
        when Copilot::INDIVIDUAL_PRO_PRODUCT_KEY
          build_upgrade(
            path: routes.copilot_pro_signup_create_path,
            return_to_path: routes.copilot_pro_signup_new_path,
            premium_requests_flag: :copilot_pro_premium_requests,
          )
        when Copilot::INDIVIDUAL_PRO_PLUS_PRODUCT_KEY
          build_upgrade(
            path: routes.copilot_pro_plus_signup_create_path,
            return_to_path: routes.copilot_pro_plus_signup_new_path,
            premium_requests_flag: :copilot_pro_plus_premium_requests,
          )
        when Copilot::INDIVIDUAL_MAX_PRODUCT_KEY
          build_upgrade(
            path: routes.copilot_max_signup_create_path,
            return_to_path: routes.copilot_max_signup_new_path,
          )
        end
      end

      private

      sig do
        params(
          path: String,
          return_to_path: String,
          premium_requests_flag: T.nilable(Symbol),
        ).returns(::Billing::PendingManualPaymentUpgrade)
      end
      def build_upgrade(path:, return_to_path:, premium_requests_flag: nil)
        params = {
          "success_path" => Rails.application.routes.url_helpers.copilot_immersive_path,
          "payment_duration" => "monthly",
          "return_to_path" => return_to_path,
          "user_contact_info" => user_contact_info,
        }

        if premium_requests_flag && FeatureFlag.vexi.enabled?(premium_requests_flag, @user, default: false)
          params["premium_requests"] = Copilot::User.new(@user).overages_enabled? ? "enabled" : "disabled"
        end

        ::Billing::PendingManualPaymentUpgrade.new(path: path, params: params)
      end

      sig { returns(T::Hash[String, T.nilable(String)]) }
      def user_contact_info
        billing_contact = @user.billing_contact
        {
          "email" => @user.email,
          "first_name" => billing_contact.first_name,
          "last_name" => billing_contact.last_name,
          "country" => billing_contact.country_code,
        }
      end
    end
  end
end
