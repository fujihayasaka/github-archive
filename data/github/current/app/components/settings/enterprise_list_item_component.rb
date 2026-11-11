# typed: strict
# frozen_string_literal: true

module Settings
  class EnterpriseListItemComponent < ApplicationComponent
    include ApplicationComponent::Rescuable
    rescue_from StandardError, with: :nothing

    sig { returns T.nilable(User) }
    attr_reader :user

    sig { returns T.nilable(Business) }
    attr_reader :business

    sig { returns String }
    attr_reader :name

    sig do
      params(
        business: T.nilable(Business),
        user: T.nilable(User),
        show_trial_information: T::Boolean,
        system_arguments: Primer::SystemArgumentsValue
      ).void
    end
    def initialize(business:, user: nil, show_trial_information: false, **system_arguments)
      @business = T.let(business, T.nilable(Business))
      @user = T.let(user, T.nilable(User))
      @name = T.let(@business ? @business.name : "", String)
      @role = T.let(@business ? @business.role_for(@user) : nil, T.nilable(Symbol))
      @show_trial_information = T.let(show_trial_information, T::Boolean)
    end

    sig { returns T::Boolean }
    def render?
      return false unless @user
      return false unless @business
      return false if @business.suspended?

      # Only render if user has a relationship to the business
      return true if @role

      # Also render for unaffiliated users when unaffiliated accounts are enabled
      return true if @business.supports_unaffiliated_user_accounts? && @business.exclusive_unaffiliated_member?(@user)

      false
    end

    private

    sig { returns T::Boolean }
    def show_trial_information?
      @show_trial_information
    end

    sig { returns String }
    memoize def trial_info
      return "none" unless @business
      return "none" unless show_trial_information?
      return "trial_days_left" if trial_days_remaining
      return "trial_expired" if @business.trial_expired?
      "none"
    end

    sig { returns T.nilable(Integer) }
    memoize def trial_days_remaining
      return unless @business
      @business.trial_days_remaining
    end

    sig { returns String }
    memoize def description
      return "Member" if @role == :member

      # Handle unaffiliated users (no formal role)
      return "Unaffiliated member" if @role.nil? && @business && @business.exclusive_unaffiliated_member?(@user)

      Business.admin_role_for(@role)
    end

    sig { returns T::Boolean }
    memoize def show_settings_button?
      Business::ADMIN_ROLES.include?(@role)
    end

    sig { returns String }
    memoize def settings_path
      case @role
      when Business::BILLING_MANAGER_ROLE
        settings_billing_enterprise_path(@business)
      else
        settings_profile_enterprise_path(@business)
      end
    end

    sig { returns T::Boolean }
    memoize def show_self_removal_button?
      return false unless @user
      return false unless @business

      # Only show for unaffiliated users and enterprise is not EMU
      return false if @business.enterprise_managed_user_enabled?
      @business.exclusive_unaffiliated_member?(@user)
    end
  end
end
