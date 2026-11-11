# typed: strict
# frozen_string_literal: true

module CodeScanning
  class ScanInactiveRepos
    sig { returns(T::Boolean) }
    def self.available_in_environment?
      GitHub.code_scanning_enabled? && !GitHub.enterprise?
    end

    sig { params(actor: T.any(Organization, Business, User)).returns(T::Boolean) }
    def self.org_settings_configurable?(actor)
      return false unless actor.is_a?(Organization)
      return false unless available_in_environment?
      return false unless feature_flag_enabled_for?(actor)

      true
    end

    sig { params(actor: T.nilable(Organization)).returns(T::Boolean) }
    def self.feature_flag_enabled_for?(actor)
      FeatureFlag.vexi.enabled?(:code_scanning_scan_inactive_repos_org_setting, actor, default: false)
    end
  end
end
