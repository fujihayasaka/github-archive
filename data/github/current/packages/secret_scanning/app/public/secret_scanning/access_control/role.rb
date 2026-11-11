# typed: strict
# frozen_string_literal: true

module SecretScanning::AccessControl
  class Role
    sig { params(user: User, repo: Repository).returns(T::Boolean) }
    def self.has_repo_security_role?(user, repo)
      repo.async_secret_scanning_check_fgp_permissions(user, :resolve_secret_scanning_alerts).sync ||
      repo.vulnerability_manager.adminable_by?(user)
    end
  end
end
