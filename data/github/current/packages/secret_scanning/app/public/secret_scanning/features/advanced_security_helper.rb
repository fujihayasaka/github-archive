# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

# Provides helper methods for Advanced Security in context of Secret Scanning
class SecretScanning::Features::AdvancedSecurityHelper
  # Indicates if advanced security is available for the given repository (ie. is this a GHAS repo)
  sig { params(repo: Repository).returns(T::Boolean) }
  def self.advanced_security_available?(repo)

    # For GHEC EMU/GHES user-owned repo's, GHAS can be configurable if allowed by the enterprise level
    if repo.owner&.user?
      ghas_for_users = AdvancedSecurity::Features::User::AdvancedSecurity.new(T.cast(repo.owner, User))
      return ghas_for_users.feature_available?
    elsif repo.owner&.organization?
      return repo.owner&.advanced_security_purchased?
    end
    false
  end

  # Indicates if advanced security configuration is available for the given repository
  #
  # This is unintuitive because we are still working within the context of a GHAS repositories only
  # The explanation is that GitHub Advanced Security is billed per active commiter ONLY in private and internal repositories
  # so public and archived repos do not have access to enabling or disabling Advanced Security so we need to ignore that setting entirely
  sig { params(repo: Repository).returns(T::Boolean) }
  def self.advanced_security_configurable?(repo)
    return false unless self.advanced_security_available?(repo)

    # not available for archived repos because they aren't billed (no active commiters)
    return false if repo.archived?

    # not available for public repos on dotcom (this includes GHAS public repos because they aren't billed)
    return false if GitHub.dotcom_request? && repo.public?

    true
  end
end
