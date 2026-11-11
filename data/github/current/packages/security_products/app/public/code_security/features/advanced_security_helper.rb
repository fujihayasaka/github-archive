# typed: strict
# frozen_string_literal: true

module CodeSecurity::Features::AdvancedSecurityHelper

  # Attempts to enable Code Security on a repository.
  # Returns a SecurityProduct::Result object detailing if the operation succeed or failed.
  sig { params(actor: User, repository: Repository, options: SecurityProduct::ServiceManager::ServiceOptions).returns(SecurityProduct::Result) }
  def self.enable_code_security(actor:, repository:, options: {})
    SecurityProduct::ServiceManager.new(repository).toggle_services(actor, services_to_enable: [[:code_security, options]])
  end

  # Attempts to enable Code Security on a repository.
  # Raises an exception if the operation fails.
  sig { params(actor: User, repository: Repository, options: T::Hash[Symbol, SecurityProduct::ServiceManager::ServiceOptions]).void }
  def self.enable_code_security!(actor:, repository:, options: {})
    error = enable_code_security(actor:, repository:, options:).error
    unless error.nil?
      Kernel.raise "Unable to enable Code Security: #{error}"
    end
  end

  # returns true if the repository can have code security
  sig { params(repository: Repository).returns T::Boolean }
  def self.code_security_should_show_in_settings?(repository:)
    return false if repository.archived?

    return false unless repository.owner&.organization?

    return true if repository.public? && !GitHub.enterprise?

    code_security_purchased_by_billable_owner?(repository:)
  end


  sig { params(repository: Repository).returns T::Boolean }
  def self.code_security_configurable?(repository:)
    return false unless code_security_should_show_in_settings?(repository:)

    GitHub.enterprise? || !repository.public?
  end

  # Indicates whether Code Security was manually enabled for this repo by a user,
  # either through the repo settings or the org "enable all" setting.
  sig { params(repository: Repository).returns T::Boolean }
  def self.code_security_enabled?(repository:)
    SecurityProduct::CodeSecurity.new(repository).enabled?
  end

  # Determines whether features that fall under Code Security are usable for this repo.
  # Handles both cases where billing is bundled or unbundled.
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.code_security_features_usable?(repository:)
    # Skip if the repo is archived
    return false if repository.archived?

    # Public repos on cloud can always use CS features
    return true if repository.public? && !GitHub.enterprise?

    # For bundled sku GHAS needs to be enabled
    return repository.advanced_security_enabled? if repository.advanced_security_products_bundled?

    # For split skus Code Security needs to be enabled
    code_security_enabled?(repository:)
  end

  sig { params(repository: Repository).returns(T::Boolean) }
  def self.code_security_purchased_by_billable_owner?(repository:)
    return GitHub::Enterprise.license.code_security_enabled if GitHub.enterprise?

    owner = repository.owner
    return false if owner.nil? || owner.is_a?(Bot) || owner.is_a?(Mannequin)
    owner.code_security_purchased?
  end

  # Indicates if there is a lock on using additional Code Security seats in metered mode
  sig { params(repository: Repository).returns(T::Boolean) }
  def self.code_security_metered_usage_locked?(repository:)
    return false if GitHub.enterprise?
    return false if repository.public?
    return false if code_security_features_usable?(repository: repository)

    # we cast owner to User so we can cover both EMU and Org repos interchangeably without extra logic
    owner = T::cast(repository.owner, User)
    owner.code_security_metered_usage_locked?
  end

  # If some _non-policy_ error prevents toggling, this method will return nil.
  # This is true even if there would also be a policy error, but the non-policy error
  # is the first one encountered (since `status` only holds a single error).
  sig { params(repository: Repository, actor: User).returns(T.nilable(Symbol)) }
  def self.code_security_toggle_not_allowed_by_policy_reason(repository:, actor:)
    product = SecurityProduct::CodeSecurity.new(repository)
    status = if product.enabled?
      product.can_disable?(actor:, options: {})
    else
      product.can_enable?(actor:, options: {})
    end

    error = status.error
    return nil unless error.is_a?(Symbol)

    error if [
      :code_security_not_allowed_by_policy,
      :code_security_restricted_by_enablement_policy,
    ].include?(error)
  end
end
