# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module SecretScanning::Features::Repo
  # Repository level enablement for Push Protection
  class PushProtection
    include GitHub::Memoizer
    include SecretScanning::Features::FeatureFlagHelper

    CONFIG_KEY_USER_ENABLED = "token_scanning_push_protection.user_enabled"

    sig { params(repo: Repository).void }
    def initialize(repo)
      @repo = repo
      @token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@repo)
    end

    # Indicate whether the feature is available for this repository
    sig { returns(T::Boolean) }
    def feature_available?
      # We do not support push protection on an archived repo as it's read-only.
      return false if @repo.archived?

      # For EMU user-owned forks, push protection is available if an ancestor has it enabled
      return true if ancestor_push_protection_enabled?

      owner = @repo.owner
      # Either the owner must have secret scanning via GHAS or GHSP, or PP should be enabled at the repo or user level for public repos.
      return false unless SecretScanning::Features::AdvancedSecurityHelper.secret_scanning_available?(@repo) ||
              (!owner.nil? && @repo.public? && feature_flag_enabled_in_hierarchy?(owner, FeatureFlags::PUSH_PROTECTION_FOR_FPR))

      # token scanning must be enabled
      return false unless @token_scanning.enabled?

      true
    end

    # Indicates whether the feature is enabled for this repository
    sig { params(ignore_import: T::Boolean).returns(T::Boolean) }
    def enabled?(ignore_import: false)
      # can't be enabled on a deleted or archived repo
      return false if @repo.deleted?
      return false if @repo.archived?

      return false unless self.feature_available?

      # ignore push protection on repository imports to avoid breaking those flows
      unless ignore_import
        return false if ImportExport.domain.is_importing?(@repo)
      end

      # For EMU user-owned forks, push protection is enabled if an ancestor has it enabled
      return true if ancestor_push_protection_enabled?

      @repo.config.enabled?(CONFIG_KEY_USER_ENABLED)
    end

    # Enable push protection for the repo.
    sig { params(actor: User).void }
    def enable(actor:)
      @repo.config.enable(CONFIG_KEY_USER_ENABLED, actor)
    end

    # Disable push protection for the repo.
    sig { params(actor: User).void }
    def disable(actor:)
      @repo.config.delete(CONFIG_KEY_USER_ENABLED, actor)
    end

    private

    # Checks if this repo is a user-owned fork in an EMU business where an ancestor has push protection enabled.
    # This allows push protection to run on forks in the network even if the fork itself doesn't have token scanning enabled.
    # Memoized to avoid repeated parent-chain traversals within the same instance.
    sig { returns(T::Boolean) }
    memoize def ancestor_push_protection_enabled?
      return false unless @repo.fork?
      owner = @repo.owner
      return false unless owner
      return false unless owner.user?
      return false unless owner.is_enterprise_managed?

      @repo.parents.any? do |parent|
        SecretScanning::Features::Repo::PushProtection.new(parent).enabled?
      end
    rescue RuntimeError
      # If the fork hierarchy is too deep, fail closed (no push protection inheritance)
      false
    end
  end
end
