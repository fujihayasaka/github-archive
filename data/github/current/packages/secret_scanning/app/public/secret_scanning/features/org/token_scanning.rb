# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Org
  class TokenScanning
    include SecretScanning::Features::FeatureFlagHelper
    SECRET_SCANNING_NEW_REPOS_KEY = "secret_scanning.new_repos_enable"

    def initialize(org)
      raise ArgumentError, "Invalid type: expected Organization but got #{org.class.name}" if !org.is_a?(Organization)

      @org = org
    end

    # Indicates whether the Token Scanning feature as a whole is available to the current organization
    def feature_available?
      # global config check
      # should be on by default for dotcom and needs to be enabled for enterprise
      return false unless GitHub.configuration_secret_scanning_enabled?

      # With free public repos being supported, secret-scanning is always available
      # at the organization level. Enablement for private repos will still be controlled
      # by billing/license checks.
      true
    end

    # Indicates whether Token Scanning is enabled for the current org
    def enabled?
      self.feature_available?
    end

    def can_enable_for_new_repos?
      true
    end

    def enable_secret_scanning_for_new_repos(actor:)
      @org.config.enable(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    def disable_secret_scanning_for_new_repos(actor:)
      @org.config.delete(SECRET_SCANNING_NEW_REPOS_KEY, actor)
    end

    def secret_scanning_enabled_for_new_repos?
      return false unless self.feature_available?

      @org.config.enabled?(SECRET_SCANNING_NEW_REPOS_KEY)
    end

    # Returns the admins to notify about secret scanning alerts for the org.
    # Also includes security managers.
    def get_admins_to_notify
      admins = @org.admins.to_a
      security_managers = SecurityProduct::SecurityManagers.new(@org)
      security_manager_user_ids = Team.user_ids_for(security_managers.teams.map { |team| team.id })
      security_manager_user_ids.concat(security_managers.directly_assigned_user_ids)
      admins += User.where(id: security_manager_user_ids)
      admins
    end

    sig { returns(T::Boolean) }
    def secret_risk_assessment_available?
      # all enterprises can buy secret protection
      return true if @org.business.present?

      # org.plan.business? is true for orgs on Teams plans
      # org.secret_protection_purchased? can be true for orgs on trials that haven't yet purchased secret protection
      # so this check aims to show assessments for Teams plan orgs on secret protection trials
      @org.plan.business? && @org.secret_protection_purchased?
    end
  end
end
