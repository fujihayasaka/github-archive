# typed: strict
# frozen_string_literal: true

module Businesses
  module AdvancedSecurity
    class TrialBannerComponent < ApplicationComponent
      extend T::Sig
      include ApplicationComponent::Rescuable

      rescue_from StandardError, with: :nothing

      sig { returns T::Hash[Symbol, T.untyped] }
      attr_reader :system_arguments

      sig { returns T.nilable(Business) }
      attr_reader :business

      sig { returns T.nilable(User) }
      attr_reader :user

      sig do
        params(
          user: T.nilable(User),
          business: T.nilable(Business),
          organization: T.nilable(Organization),
          system_arguments: T.untyped
        ).void
      end
      def initialize(user:, business:, organization: nil, **system_arguments)
        @user = user
        @business = business
        @organization = organization
        @system_arguments = system_arguments
        @system_arguments[:display] = [:block, nil, :flex, nil, nil] unless @system_arguments.key?(:display)
        @system_arguments[:align_items] = :center unless @system_arguments.key(:align_items)
        @system_arguments[:justify_content] = :space_between unless @system_arguments.key?(:justify_content)
        @system_arguments[:py] = 2 unless @system_arguments.key?(:py)
        @system_arguments[:px] = [3, nil, 4, 5, nil] unless @system_arguments.key?(:px)
        @system_arguments[:font_size] = 6 unless @system_arguments.key?(:font_size)
        @system_arguments[:bg] = :accent unless @system_arguments.key?(:accent)
      end

      sig { returns(T::Boolean) }
      def render?
        return false unless @business
        return false unless @user
        return false unless GitHub.billing_enabled?
        return false if GitHub.multi_tenant_enterprise?
        return false if @business.trial?
        return false unless can_manage_business || can_manage_organization
        @business.has_active_advanced_security_trial?
      end

      private

      sig { returns(T.nilable(Organization)) }
      memoize def organization
        @organization || @business&.organization_for_advanced_security_trial(actor: T.must(user))
      end

      sig { returns(T.nilable(Integer)) }
      memoize def trial_days_left
        return nil unless @business
        @business.advanced_security_subscription_item&.days_left_on_free_trial
      end

      sig { returns(T::Boolean) }
      memoize def can_manage_business
        return false unless @business
        @business.adminable_by?(@user)
      end

      sig { returns(T::Boolean) }
      memoize def can_manage_organization
        return false unless org = organization
        org.adminable_by?(@user)
      end
    end
  end
end
