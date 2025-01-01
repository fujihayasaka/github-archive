# typed: strict
# frozen_string_literal: true

# Provides helper methods for Advanced Security in context of Secret Scanning
class SecretScanning::Features::AdvancedSecurityHelper
  include SecretScanning::Features::FeatureFlagHelper

  # Indicates if advanced security is available for the given entity (ie. is this a GHAS repo)
  sig { params(entity: T.any(Repository, User, Organization)).returns(T::Boolean) }
  def self.advanced_security_available?(entity)
    owner = entity
    owner = entity.owner if entity.is_a?(Repository)
    return false unless owner

    owner = T.cast(owner, T.any(User, Organization))
    # For GHEC EMU/GHES user-owned repo's, GHAS can be configurable if allowed by the enterprise level
    if owner.instance_of?(User)
      ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(owner)
      return ghas_for_users.feature_available?
    elsif owner.is_a?(Organization)
      return owner.advanced_security_purchased?
    end
    false
  end

  # Indicates if the secret scanning SKU (GHSP) is available for the given entity
  sig { params(entity: T.any(Repository, User, Organization)).returns(T::Boolean) }
  def self.secret_scanning_available?(entity)
    owner = entity
    owner = entity.owner if entity.is_a?(Repository)
    return false unless owner

    owner = T.cast(owner, T.any(User, Organization))
    if GitHub.enterprise?
      return false if owner.user? && !GitHub.ghas_for_enterprise_users_enabled?
      return true if GitHub.ghas_sku_split_enabled? && owner.secret_protection_purchased?
    end

    return true if owner.secret_protection_purchased?
    self.advanced_security_available?(entity) && owner.advanced_security_products_bundled?
  end

  # Returns true if GHSP was paid for, either through GHAS or
  # through enabling GHSP on a private repo in the past
  # (even if those repos are no longer paying for GHSP).
  sig { params(entity: Organization).returns(T::Boolean) }
  def self.secret_scanning_paid_for?(entity)
    return false unless secret_scanning_available?(entity) # Ensure unbundled-GHSP or bundled-GHAS is purchased somehow
    if entity.plan.business?
      return false unless Repository::SecurityCenterBusinessPlanOrgEligibility.enabled?(entity) # For Team Orgs only, ensure they have incurred charges at least once
    end
    true
  end

  # Indicates if bundled GHAS configuration is available for the given repository
  #
  # This is unintuitive because we are still working within the context of a GHAS repositories only
  # The explanation is that GitHub Advanced Security is billed per active commiter ONLY in private and internal repositories
  # so public and archived repos do not have access to enabling or disabling Advanced Security so we need to ignore that setting entirely
  sig { params(repo: Repository).returns(T::Boolean) }
  def self.bundled_ghas_configurable?(repo)
    return false unless self.advanced_security_available?(repo)

    return false unless repo.owner&.advanced_security_products_bundled?

    # not available for archived repos because they aren't billed (no active commiters)
    return false if repo.archived?

    # not available for public repos on dotcom (this includes GHAS public repos because they aren't billed)
    return false if GitHub.dotcom_request? && repo.public?

    true
  end

  # Indicates if secret scanning is enabled for the given Repository
  #
  # To be enabled, the repository must have secret scanning available and have it enabled in its settings
  sig { params(repo: Repository).returns(T::Boolean) }
  def self.secret_scanning_enabled?(repo)
    return false unless self.secret_scanning_available?(repo)
    ::SecretScanning::Features::Repo::TokenScanning.new(repo).enabled?
  end
end
