# typed: strict
# frozen_string_literal: true

module Configurable
  module CodeScanningScanInactiveRepos
    extend T::Helpers

    requires_ancestor { Configurable }

    CODE_SCANNING_SCAN_INACTIVE_REPOS_ENABLEMENT_KEY = "code_scanning_scan_inactive_repos.enablement"

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def enable_code_scanning_scan_inactive_repos_settings(actor:)
      config.enable(CODE_SCANNING_SCAN_INACTIVE_REPOS_ENABLEMENT_KEY, actor)
    end

    sig { params(actor: Users::IUser).returns(T.nilable(T::Boolean)) }
    def disable_code_scanning_scan_inactive_repos_settings(actor:)
      config.disable(CODE_SCANNING_SCAN_INACTIVE_REPOS_ENABLEMENT_KEY, actor)
    end

    sig { returns(T::Boolean) }
    def code_scanning_scan_inactive_repos_settings_enabled?
      config.enabled?(CODE_SCANNING_SCAN_INACTIVE_REPOS_ENABLEMENT_KEY)
    end
  end
end
