# typed: true
# frozen_string_literal: true

module GitAuth
  class GotAuthFeatureFlags
    # NOTE: We could generate the following feature flag symbols dynamically, but doing so would make it harder to locate their references through code search.

    sig { params(action: String, public_request: T::Boolean, repository: T.nilable(T.any(Repository, GitAuth::Gist))).returns(T::Boolean) }
    def self.is_mirroring_enabled?(action, public_request, repository)
      return false unless action == "read" || action == "write"

      if public_request
        return true if action == "read" && GitHub.flipper[:gotauth_mirror_public_read_dark_ship].enabled?
        return true if action == "write" && GitHub.flipper[:gotauth_mirror_public_write_dark_ship].enabled?
      else
        return true if GitHub.flipper[:gotauth_mirror_private_dark_ship].enabled?
      end

      return true if repository && repository.is_a?(Repository) && repository.feature_enabled?(:gotauth_mirror)

      if GitHub.deployed_to == "gitauth-lab"
        return true if repository && repository.is_a?(Repository) && repository.feature_enabled?(:gotauth_mirror_lab)
        return true if GitHub.flipper[:gotauth_mirror_lab].enabled?
      end

      GitHub.flipper[:gotauth_mirror].enabled?
    end

    sig { params(action: String, public_request: T::Boolean, repository: T.nilable(T.any(Repository, GitAuth::Gist))).returns(T::Boolean) }
    def self.is_mirroring_result_use_enabled?(action, public_request, repository)
      return false unless action == "read" || action == "write"

      if public_request
        if action == "read"
          return true if repository.is_a?(Repository) && repository.public? && repository.feature_enabled?(:gotauth_mirror_public_read_use_result)
          return true if GitHub.flipper[:gotauth_mirror_public_read_use_result].enabled?
        else
          return true if repository.is_a?(Repository) && repository.public? && repository.feature_enabled?(:gotauth_mirror_public_write_use_result)
          return true if GitHub.flipper[:gotauth_mirror_public_write_use_result].enabled?
        end
      else
        return true if repository.is_a?(Repository) && repository.private? && repository.feature_enabled?(:gotauth_mirror_private_use_result)
        return true if GitHub.flipper[:gotauth_mirror_private_use_result].enabled?
      end

      false
    end

    sig { params(action: String, repository: T.any(Repository, GitAuth::Gist)).returns(T::Boolean) }
    def self.is_redirect_enabled?(action, repository)
      return false unless action == "read" || action == "write"
      return false if repository.nil?
      return false if repository.is_a?(Repository) && repository.feature_enabled?(:gotauth_redirect_opt_out)
      return false if repository.is_a?(GitAuth::Gist) && GitHub.flipper[:gotauth_redirect_opt_out].enabled?

      flag = if repository.public?
        if action == "read"
          :gotauth_redirect_public_read
        else
          :gotauth_redirect_public_write
        end
      else
        :gotauth_redirect_private
      end

      return true if repository.is_a?(Repository) && repository.feature_enabled?(flag)
      return true if repository.is_a?(GitAuth::Gist) && GitHub.flipper[flag].enabled?

      false
    end
  end
end
