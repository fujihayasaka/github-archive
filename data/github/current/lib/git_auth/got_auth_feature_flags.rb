# typed: true
# frozen_string_literal: true

module GitAuth
  class GotAuthFeatureFlags
    # NOTE: We could generate the following feature flag symbols dynamically, but doing so would make it harder to locate their references through code search.

    sig { params(action: String, public_request: T::Boolean, repository: T.nilable(T.any(Repository, GitAuth::Gist))).returns(T::Boolean) }
    def self.is_mirroring_enabled?(action, public_request, repository)
      return false unless action == "read" || action == "write"

      if public_request
        return true if action == "read" && FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_public_read_dark_ship) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        return true if action == "write" && FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_public_write_dark_ship) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      else
        return true if action == "read" && FeatureFlag.vexi.enabled?(:gotauth_mirror_private_read_dark_ship, default: false)
        return true if action == "write" && FeatureFlag.vexi.enabled?(:gotauth_mirror_private_write_dark_ship, default: false)
      end

      return true if is_repository_feature_enabled?(repository, :gotauth_mirror)

      if GitHub.deployed_to == "gitauth-lab"
        return true if is_repository_feature_enabled?(repository, :gotauth_mirror_lab)
        return true if FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_lab) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      end

      FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    end

    sig { params(action: String, public_request: T::Boolean, repository: T.nilable(T.any(Repository, GitAuth::Gist))).returns(T::Boolean) }
    def self.is_mirroring_result_use_enabled?(action, public_request, repository)
      return false unless action == "read" || action == "write"

      if public_request
        if action == "read"
          return true if repository.is_a?(Repository) && repository.public? && is_repository_feature_enabled?(repository, :gotauth_mirror_public_read_use_result)
          return true if FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_public_read_use_result) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        else
          return true if repository.is_a?(Repository) && repository.public? && is_repository_feature_enabled?(repository, :gotauth_mirror_public_write_use_result)
          return true if FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_public_write_use_result) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        end
      else
        if action == "read"
          return true if repository.is_a?(Repository) && repository.private? && is_repository_feature_enabled?(repository, :gotauth_mirror_private_read_use_result)
          return true if FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_private_read_use_result) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        else
          return true if repository.is_a?(Repository) && repository.private? && is_repository_feature_enabled?(repository, :gotauth_mirror_private_write_use_result)
          return true if FeatureFlag.vexi.enabled_or_raise?(:gotauth_mirror_private_write_use_result) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        end
      end

      false
    end

    sig { params(action: String, repository: T.any(Repository, GitAuth::Gist)).returns(T::Boolean) }
    def self.is_redirect_enabled?(action, repository)
      return false unless action == "read" || action == "write"
      return false if repository.nil?
      return false if is_repository_feature_enabled?(repository, :gotauth_redirect_opt_out)
      return false if repository.is_a?(GitAuth::Gist) && FeatureFlag.vexi.enabled_or_raise?(:gotauth_redirect_opt_out) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      flag = if repository.public?
        if action == "read"
          :gotauth_redirect_public_read
        else
          :gotauth_redirect_public_write
        end
      elsif action == "read"
        :gotauth_redirect_private_read
      else
        :gotauth_redirect_private_write
      end

      return true if is_repository_feature_enabled?(repository, flag)
      return true if repository.is_a?(GitAuth::Gist) && FeatureFlag.vexi.enabled_or_raise?(flag) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

      false
    end

    # This method ensures the repository check runs before the owner check, so we only load the underlying
    # owner model when absolutely necessary.
    sig { params(repository: T.nilable(T.any(Repository, GitAuth::Gist)), feature_flag: Symbol).returns(T::Boolean) }
    private_class_method def self.is_repository_feature_enabled?(repository, feature_flag)
      return false unless repository.is_a?(Repository)

      return true if repository.feature_flag_enabled?(feature_flag, default: false)

      return false unless FeatureFlag.vexi.enabled?(:gotauth_mirror_or_redirect_owner_check, default: false)

      repository.owner&.feature_flag_enabled?(feature_flag, default: false) || false
    end
  end
end
