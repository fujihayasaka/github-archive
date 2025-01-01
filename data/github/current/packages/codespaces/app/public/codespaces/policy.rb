# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class Policy

    # Whether to show the entitlements feature & functionality
    # Checks FF & if the billable owner is on an entitlements enabled plan
    def self.entitlements_feature_enabled?(actor)
      return false unless actor

      # Entitlements are not available for organizations
      return false if actor.organization? || actor.instance_of?(::Business)

      # Entitlements for Codespaces are only available for free & pro users
      return false unless actor.plan
      %w[pro free_user].include?(actor.plan.entitlement_plan_name)
    end

    # How many codespaces can the user have?
    def self.codespaces_limit(user)
      # We make an exception for users giving demos where they need to have many, long-lived codespaces.
      # We are consciously trying to avoid this for geniune development to share the customer experience.
      if FeatureFlag.vexi.enabled_or_raise?(:codespaces_per_user_sales_demo_limit, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        GitHub.codespaces_per_user_sales_demo_limit
      elsif FeatureFlag.vexi.enabled_or_raise?(:codespaces_automated_testing, user) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        GitHub.codespaces_automated_testing_limit
      else
        tier = Codespaces::Tier.for_user(user)
        Codespaces::Tier.config_for_tier(tier, user).codespaces_per_user
      end
    end

    def self.can_receive_secrets?(codespace)
      return false if secrets_disabled?

      codespace.repository.pushable_by?(codespace.owner)
    end

    def self.can_receive_all_secrets?(codespace)
      can_receive_secrets?(codespace)
    end

    def self.secrets_disabled?
      FeatureFlag.vexi.enabled_or_raise?(:disable_codespaces_secrets) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    def self.codespace_user_spammy?(codespace)
      (codespace&.owner&.present? && codespace.owner.spammy?) ||
      (codespace&.repository&.owner&.present? && codespace.repository.owner.spammy?) ||
      (codespace&.billable_owner&.present? && codespace.billable_owner.spammy?)
    end
  end
end
