# typed: strict
# frozen_string_literal: true
module Settings
  class EnterpriseListItemComponent < ApplicationComponent
    extend T::Sig
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
        system_arguments: T.untyped
      ).void
    end
    def initialize(business:, user: nil, show_trial_information: false, **system_arguments)
      @business = business
      @user = user
      @name = T.let(@business ? @business.name : "", String)
      @role = T.let(@business ? @business.role_for(@user) : nil, T.nilable(Symbol))
      @show_trial_information = show_trial_information
    end

    sig { returns T::Boolean }
    def render?
      return false unless @user
      return false unless @business
      return false unless @role
      return false if @business.suspended?
      true
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
  end
end
