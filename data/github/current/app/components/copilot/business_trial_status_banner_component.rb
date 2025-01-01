# typed: strict
# frozen_string_literal: true

module Copilot
  class BusinessTrialStatusBannerComponent < ApplicationComponent


    sig { returns(BusinessTrial) }
    attr_reader :business_trial

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :show_after_expired

    sig { returns(T.nilable(T::Boolean)) }
    attr_reader :within_tile

    sig { params(business_trial: BusinessTrial, show_after_expired: T::Boolean, within_tile: T::Boolean).void }
    def initialize(business_trial:, show_after_expired: false, within_tile: false)
      @business_trial = business_trial
      @show_after_expired = show_after_expired
      @within_tile = within_tile
    end

    sig { returns(T::Boolean) }
    def render?
      return false if business_trial.pending?
      return false if trial_organization.nil?
      business = trial_organization&.business
      return false if business && business.digital_front_door?

      # This indicates that the organization has a direct plan, under mixed licensing.
      # A plan should only be configured for an org without an active trial.
      # We want to check this before checking if the trial is expired, because the trial could have been allowed to expire,
      # but a license may still have been assigned under mixed licensing.
      return false if business_trial.copilot_plan_business? && trial_copilot_organization.has_configured_copilot_plan? && trial_copilot_organization.copilot_plan_business?
      return false if business_trial.copilot_plan_enterprise? && trial_copilot_organization.has_configured_copilot_plan? && trial_copilot_organization.copilot_plan_enterprise?
      return true if @show_after_expired && business_trial.expired? && !copilot_trial_upgraded?
      business_trial.final_day?
    end

    sig { returns(T::Boolean) }
    def copilot_plan_enterprise?
      trial_copilot_organization.copilot_plan_enterprise?
    end

    sig { returns(String) }
    def trial_expired_message
      if business_trial.copilot_plan_business?
        "Your GitHub Copilot free trial has expired."
      else
        "Your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial has expired and your access has been downgraded to #{Copilot.business_product_name}."
      end
    end

    sig { returns(String) }
    def trial_expiring_today_message
      if business_trial.copilot_plan_business?
        "Your GitHub Copilot free trial expires today."
      else
        "Your GitHub #{Copilot::ENTERPRISE_PRODUCT_NAME} trial expires today."
      end
    end

    sig { returns(String) }
    def trial_upgrade_instruction_message
      trial_upgrade_actor = business_trial.expired? ? "enterprise administrator" : "sales representative"

      return "Upgrade to the paid version by contacting your #{trial_upgrade_actor}." if trial_organization&.business&.present?

      # Standalone organizations will always need to contact a sales rep to upgrade.
      "Upgrade to the paid version by contacting your sales representative."
    end

    private

    sig { returns(String) }
    def copilot_enterprise_signup_payment_link
      message = business_trial.expired? ? "You can purchase #{Copilot::ENTERPRISE_PRODUCT_NAME}" : "Upgrade to the paid version of #{Copilot::ENTERPRISE_PRODUCT_NAME}"
      render(Primer::Beta::Link.new(
        href: copilot_enterprise_signup_payment_path(enterprise: T.must(trial_organization).business),
        classes: "Link--inTextBlock"
        )) { message }
    end

    sig { returns Copilot::Organization }
    memoize def trial_copilot_organization
      Copilot::Organization.new(T.must(trial_organization))
    end

    sig { returns(T::Boolean) }
    def copilot_trial_upgraded?
      return true if business_trial.copilot_plan_business? && trial_copilot_organization.copilot_enabled?
      return true if business_trial.copilot_plan_enterprise? && copilot_plan_enterprise?
      false
    end

    sig { returns(T.nilable(::Organization)) }
    memoize def trial_organization
      business_trial.trialable
    end
  end
end
