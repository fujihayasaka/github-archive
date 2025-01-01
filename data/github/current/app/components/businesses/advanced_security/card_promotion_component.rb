# typed: strict
# frozen_string_literal: true
module Businesses
  module AdvancedSecurity
    class CardPromotionComponent < ApplicationComponent
      include ApplicationComponent::Rescuable

      rescue_from StandardError, with: :nothing

      NOTICE_NAME = "advanced_security_sidebar_promotion"

      sig { returns T.nilable(Business) }
      attr_reader :business

      sig { returns T.nilable(User) }
      attr_reader :user

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig do
        params(
          user: T.nilable(User),
          business: T.nilable(Business),
          system_arguments: T.untyped).void
      end
      def initialize(user: nil, business: nil, **system_arguments)
        @user = user
        @business = business
        @system_arguments = system_arguments
        # hide the card in smaller viewports, because the sidebar currently looks wrong in this state
        @system_arguments[:display] = [:none, nil, nil, :block, nil] unless @system_arguments.key?(:display)
        @system_arguments[:classes] = class_names("js-notice", @system_arguments[:classes])
      end

      sig { returns String }
      def notice_name
        NOTICE_NAME
      end

      sig { returns T::Boolean }
      def render?
        return false unless @business
        return false unless @user
        return false if GitHub.enterprise?
        return false if GitHub.multi_tenant_enterprise?
        return false if @user.dismissed_business_notice?(notice_name, business_id: @business.id)
        return false unless @business.adminable_by?(@user)
        return false unless potentially_trial_or_purchase_advanced_security?
        return false unless eligible_for_self_serve_advanced_security_trial? || eligible_for_self_serve_advanced_security?
        return false unless @business.eligible_for_self_serve_payment?    # Don't show this for invoiced businesses
        return false if @business.advanced_security_purchased_for_entity? # if any form of Advanced Security is enabled
        return false if @user.is_first_emu_owner? && !@business.saml_provider&.scim_provisioning_state_enabled?
        true
      end

      sig { returns T::Boolean }
      memoize def eligible_for_self_serve_advanced_security?
        return false unless @business
        @business.eligible_for_self_serve_advanced_security?(skip_shared_checks: true)
      end

      sig { returns T::Boolean }
      memoize def eligible_for_self_serve_advanced_security_trial?
        return false unless @business
        @business.eligible_for_self_serve_advanced_security_trial?(skip_shared_checks: true)
      end

      sig { returns T::Boolean }
      memoize def potentially_trial_or_purchase_advanced_security?
        return false unless @business
        @business.potentially_trial_or_purchase_advanced_security?
      end

      sig { returns Integer }
      memoize def trial_length
        return 30 unless @business
        @business.new_advanced_security_trial_days
      end

      sig { returns(String) }
      def buy_button_path
        return "" unless @business
        return billing_settings_advanced_security_upgrade_enterprise_path(@business) if @business.eligible_for_self_serve_payment?
        return billing_renew_enterprise_path(@business) if @business.eligible_for_renewal?
        return billing_add_seats_enterprise_path(@business) if @business.eligible_for_upgrade?
        ""
      end
    end
  end
end
