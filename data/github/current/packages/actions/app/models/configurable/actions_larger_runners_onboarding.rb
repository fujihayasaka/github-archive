# typed: false
# frozen_string_literal: true

module Configurable
  module ActionsLargerRunnersOnboarding
    include Instrumentation::Model

    LARGER_RUNNERS_ONBOARDED_KEY = "actions_larger_runners_onboarded".freeze

    # It is a main method which should be used to check that entity (organization or enterprise) can use Larger Runners
    # It validates that account is eligible to use Larger Runners and account has been onboarded already
    # The method returns true only if entity or parent entity was explicitly onboarded using "onboard_larger_runners" to avoid unnecessary host failt-in in Runner service
    # This function must be always invoked before making requests to Runner service
    def can_use_larger_runners?
      return false unless self.is_eligible_to_use_larger_runners?

      return true if self.is_larger_runners_onboarded?

      if self.is_a?(Organization) && self.business.present?
        return true if self.business.is_larger_runners_onboarded?
      end

      false
    end

    # It is internal method which determines if entity is onboarded to Larger Runners or not
    # Account is onboarded on first usage. So this flag is set to true if user has ever created any runner, access feature UI or access feature API.
    # The value of this flag is equal to existence of host in Runner service for account.
    # This method is not intended to be used directly except very specific cases when you only need to know if host exists
    # Prefer using "can_use_larger_runners?" method to check if account can access Larger Runners because
    # Account can be onboarded but ineligible to use Larger Runners (cases when account was downgraded, marked as spammy, etc)
    def is_larger_runners_onboarded?
      return @is_larger_runners_onboarded if defined?(@is_larger_runners_onboarded)

      # Fallback to false if Configuration database is not available to unblock shared pages like "Runners" or "Runner groups"
      @is_larger_runners_onboarded = with_database_error_fallback(fallback: false) do
        # By default config can inherit settings from parent entities.
        # If entity doesn't have own setting, consider it as non-onboarded
        return false unless config.local?(LARGER_RUNNERS_ONBOARDED_KEY)
        config.enabled?(LARGER_RUNNERS_ONBOARDED_KEY)
      end
    end

    def onboard_larger_runners(actor:)
      if self.is_larger_runners_onboarded?
        return
      end

      # there are cases when account can be onboarded from GET request or background job
      # In these cases we don't have writing database connection by default so we need to establish it manually
      ActiveRecord::Base.connected_to(role: :writing) do
        if config.enable(LARGER_RUNNERS_ONBOARDED_KEY, actor)
          @is_larger_runners_onboarded = true
          GitHub::Logger.info({
            msg: "actions_larger_runners_onboard_entity",
            "entity.login": self.is_a?(Business) ? self.slug : self.display_login,
            "entity.class": self.class.to_s })
          GitHub.dogstats.increment("actions_larger_runners.onboard_entity")
        end
      end
    end

    def self.larger_runners_onboarded_businesses
      onboarded_ids = Configuration::Entry
        .targeting_businesses
        .named(LARGER_RUNNERS_ONBOARDED_KEY)
        .with_true_value
        .pluck(:target_id)
      Business.where(id: onboarded_ids)
    end

    def self.larger_runners_onboarded_organizations
      onboarded_ids = Configuration::Entry
        .targeting_users
        .named(LARGER_RUNNERS_ONBOARDED_KEY)
        .with_true_value
        .pluck(:target_id)
      Organization.where(id: onboarded_ids)
    end

    def is_eligible_to_use_larger_runners?
      return @is_eligible_to_use_larger_runners if defined?(@is_eligible_to_use_larger_runners)

      @is_eligible_to_use_larger_runners = with_database_error_fallback(fallback: false) do
        billing_owner = self.is_a?(Organization) && self.business.present? ? self.business : self
        if GitHub.flipper[:larger_runners_skip_eligible_to_use_validation].enabled?(billing_owner)
          return true
        end

        return false unless GitHub.actions_larger_runners_enabled?

        return false if self.spammy?

        if self.is_a?(Business)
          return false if self.downgraded_to_free_plan?
        elsif self.is_a?(Organization)
          return false unless self.plan.business? || # "Team" billing plan
                              self.plan.business_plus? || # "Enterprise" billing plan
                              self.plan.enterprise? # It is "Enterprise" billing plan for GitHub Enterprise
        end

        true
      end
    end

    def is_eligible_to_onboard_larger_runners?
      return @is_eligible_to_onboard_larger_runners if defined?(@is_eligible_to_onboard_larger_runners)

      @is_eligible_to_onboard_larger_runners = with_database_error_fallback(fallback: false) do
        billing_owner = self.is_a?(Organization) && self.business.present? ? self.business : self
        if GitHub.flipper[:larger_runners_skip_eligible_to_use_validation].enabled?(billing_owner)
          return true
        end

        return false unless self.is_eligible_to_use_larger_runners?

        # Don't allow accounts on trial billing plan to onboard Larger Runners
        if billing_owner.is_a?(Business)
          return false if billing_owner.trial?
        elsif billing_owner.is_a?(Organization)
          return false if billing_owner.on_enterprise_cloud_trial?
        end

        true
      end
    end
  end
end
