# typed: strict
# frozen_string_literal: true

module AdvancedSecurity
  class TrialExpiredBannerComponent < ApplicationComponent
    include ApplicationComponent::Rescuable

    rescue_from StandardError, with: :nothing

    # Number of days after trial expiry to continue showing the expired banner
    EXPIRED_BANNER_DISPLAY_DAYS = 30

    sig { returns(T.any(Business, Organization)) }
    attr_reader :billable_entity

    sig { returns(T.nilable(User)) }
    attr_reader :user

    sig do
      params(
        user: T.nilable(User),
        billable_entity: T.any(Business, Organization),
        organization: T.nilable(Organization),
      ).void
    end
    def initialize(user:, billable_entity:, organization: nil)
      @user = user
      @billable_entity = billable_entity
      @organization = organization
    end

    sig { returns(T::Boolean) }
    def render?
      return false unless @user
      return false unless GitHub.billing_enabled?
      return false unless FeatureFlag.vexi.enabled?("ghas_self_serve_trial_expired_banner", @billable_entity, default: false)
      return false if dfd_trial_banner_showing?
      return false unless @billable_entity.advanced_security_free_trial_expired?
      return false unless standalone_trial_requires_renewal?
      return false unless within_display_window?
      return false unless can_manage_business || can_manage_organization

      true
    end

    sig { returns(T::Boolean) }
    def enterprise_admin?
      can_manage_business
    end

    sig { returns(String) }
    def buy_button_href
      if can_manage_business
        settings_security_analysis_enterprise_path(@billable_entity)
      elsif (org = organization)
        settings_org_security_products_path(org)
      else
        "#"
      end
    end

    private

    sig { returns(T::Boolean) }
    def dfd_trial_banner_showing?
      @billable_entity.is_a?(Business) && (@billable_entity.trial? || @billable_entity.trial_expired?)
    end

    sig { returns(T::Boolean) }
    def standalone_trial_requires_renewal?
      standalone_trials.any? &&
        standalone_trials.none?(&:feature_is_in_use?) &&
        standalone_trials.none?(&:ghas_is_in_use?)
    end

    sig { returns(T::Boolean) }
    def within_display_window?
      ended_dates = standalone_trials.map(&:ended_at).compact
      return false if ended_dates.empty?

      most_recent_end = T.must(ended_dates.max)
      most_recent_end >= EXPIRED_BANNER_DISPLAY_DAYS.days.ago.to_date
    end

    sig { returns(T::Array[EnterpriseCloudOnboard::SKUTrial]) }
    memoize def standalone_trials
      [@billable_entity.secret_protection_trial, @billable_entity.code_security_trial]
        .select { |t| t.ended_at.present? && t.trial_type == EnterpriseCloudOnboard::AdvancedSecurityTrial::GHAS_STAND_ALONE }
    end

    sig { returns(T::Boolean) }
    memoize def can_manage_business
      @billable_entity.adminable_by?(@user)
    end

    sig { returns(T::Boolean) }
    memoize def can_manage_organization
      return false unless org = organization
      org.adminable_by?(@user)
    end

    sig { returns(T.nilable(Organization)) }
    memoize def organization
      @organization || @billable_entity.organization_for_advanced_security_trial(actor: T.must(user))
    end
  end
end
