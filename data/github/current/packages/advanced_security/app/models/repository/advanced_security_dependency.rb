# typed: true
# frozen_string_literal: true

module Repository::AdvancedSecurityDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  include SecretScanning::Features::FeatureFlagHelper

  requires_ancestor { Repository }

  included do
    T.bind(self, T.class_of(Repository))
    # Repositories that must enable advanced security in order to use advanced security features.
    # Does not include repositories where advanced security is enabled by default.
    scope :can_enable_advanced_security, ->(owner_type = :organization) do
      rel = active.not_archived_scope
      return rel if owner_type == :user

      rel = rel.org_owned
      rel = rel.private_scope unless GitHub.enterprise?
      rel
    end
  end

  # Attempts to enable advanced security on the current repository.
  # Returns a SecurityProduct::Result object detailing if the operation succeed or failed.
  def enable_advanced_security(actor:)
    T.bind(self, Repository)
    SecurityProduct::ServiceManager.new(self).toggle_services(actor, services_to_enable: [:advanced_security])
  end

  # Attempts to enable advanced security on the current repository.
  # Raises an exception if the operation fails.
  def enable_advanced_security!(actor:)
    error = enable_advanced_security(actor: actor).error
    unless error.nil?
      raise "Unable to enable advanced security: #{error}"
    end
  end

  # Attempts to disable advanced security on the current repository.
  # Returns a SecurityProduct::Result object detailing if the operation succeed or failed.
  def disable_advanced_security(actor:, owner: nil)
    T.bind(self, Repository)
    SecurityProduct::ServiceManager.new(self).toggle_services(actor, services_to_disable: [[:advanced_security, { owner: owner }]])
  end

  # Attempts to disable advanced security on the current repository.
  # Raises an exception if the operation fails.
  def disable_advanced_security!(actor:, owner: nil)
    error = disable_advanced_security(actor: actor, owner: owner).error
    unless error.nil?
      raise "Unable to disable advanced security: #{error}"
    end
  end

  # Indicates whether Advanced Security was manually enabled for this repo by a user,
  # either through the repo settings or the org "enable all" setting.
  sig { returns(T::Boolean) }
  def advanced_security_enabled?
    T.bind(self, Repository)
    SecurityProduct::AdvancedSecurity.new(self).enabled?
  end

  # Indicates whether Advanced Security features are usable for this repo.
  def advanced_security_usable?
    # check that GHAS is turned on for the repo (includes license check)
    return advanced_security_enabled? if GitHub.enterprise?

    # GHAS is always enabled for public repos on dotcom,
    # or otherwise check GHAS is purchased and enabled
    public? || advanced_security_enabled?
  end

  # Can Advanced Security be enabled/disabled on this repo.
  def advanced_security_configurable?
    # For public repos on dotcom, GHAS is not configurable
    return false if GitHub.dotcom_request? && public?

    T.bind(self, Repository)
    # This is false for unbundled scenarios on orgs and businesses when sku split is enabled
    advanced_security_products_bundled? && owner&.advanced_security_configurable?
  end

  # Are advanced security features bundled or split for this repository?
  sig { returns(T::Boolean) }
  def advanced_security_products_bundled?
    local_owner = owner
    return false unless local_owner
    local_owner.advanced_security_products_bundled?
  end

  # Should we enforce license limits for GHAS when a user tries to enable GHAS on this repository.
  # Generally this is true iff GHAS is purchased, but if the advanced_security_circuit_breaker
  # feature flag is enabled as a temporary workaround for a bug, then we don't enforce limits even
  # if GHAS is purchased.
  def enforce_advanced_security_committers_limits?
    owner&.enforce_advanced_security_committers_limits?
  end

  # Whether advanced security should be enabled when this repository transitions
  # into an eligible state (e.g. public to internal, public to private, internal
  # to private, unarchived).
  # Covers whether GHAS is purchased, if GHAS is enabled on new repos, and if
  # the license seat limit would be exceeded.
  def enable_advanced_security_on_state_change?
    T.bind(self, Repository)
    local_owner = T.must(self.owner)
    # Enable GHAS on repo state change if the repo is private or internal, or in
    # any state on GitHub Enterprise, and is owned by an organization which has
    # set GHAS to be automatically enabled on new repos.
    return false if self.public? && !GitHub.enterprise?
    return false unless local_owner.organization?
    return false unless local_owner.advanced_security_enabled_on_new_repos?
    return false unless policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL)
    !(self.enforce_advanced_security_committers_limits? && local_owner.advanced_security_license.enabling_repo_exceeds_seat_allowance?(self))
  end

  sig { returns(T::Boolean) }
  def advanced_security_locked_by_metered_usage?
    T.bind(self, Repository)
    local_owner = T.must(self.owner)
    return false if GitHub.enterprise?
    return false if self.public?
    return false unless self.advanced_security_products_bundled?
    # At this point we know GHAS is bundled
    return false if self.advanced_security_enabled?
    local_owner.advanced_security_metered_usage_locked?
  end

  private

  # This method covers both whether we SHOULD enable GHAS, and whether we CAN enable GHAS on a new repo
  def enable_advanced_security_on_new_repo?
    T.bind(self, Repository)
    local_owner = T.must(self.owner)

    # If the repository is owned by an organization with security configurations enabled but there is no default configuration,
    # we want to to infer GHAS enablement on the repository from the business.
    # If the repository is not org owned, we just check to see if the user has advancedd security enabled
    # for new repos and return that.
    if local_owner.security_configurations_enabled?
      return false unless local_owner.business&.advanced_security_enabled_on_new_repos? # SHOULD
    else
      return false unless local_owner.advanced_security_enabled_on_new_repos? # SHOULD
    end

    return false unless self.policy_allows_advanced_security_enablement?(sku: Configurable::AdvancedSecurityAccessPolicy::ENTITY_ALLOWED_ALL) # CAN
    !(self.enforce_advanced_security_committers_limits? && local_owner.advanced_security_license.allowance_exceeded?) # CAN
    # NOTE: As this is for a brand new repo, we will not be adding more committers. Thus the check above
    #       only cares about whether we are currently over the limit.
  end
end
