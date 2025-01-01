# typed: true
# frozen_string_literal: true

module Settings
  class SecurityGlobalSettingsFormComponent < ApplicationComponent

    attr_reader :private_repo_count, :public_repo_count, :repo_count

    def initialize(owner:, public_repo_count:, repo_count:, cursor:, custom_patterns_query: "")
      @owner = owner
      @private_repo_count = repo_count - public_repo_count
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @cursor = cursor
      @custom_patterns_query = custom_patterns_query
    end

    def render?
      @owner.security_configurations_enabled?
    end

    def ghas_settings_path
      settings_org_security_analysis_ghas_settings_path(
        @owner,
        cursor: @cursor,
        custom_patterns_query: @custom_patterns_query,
        tip: params[:tip],
      )
    end

    def dependabot_rules_enabled?
      @owner.organization? && GitHub.dependabot_rules_enabled?
    end

    private

    # Dependabot updates enablement settings shouln't be currently
    # available at the business/enterprise level on GHES/GHEC
    memoize def show_dependabot_updates_settings?
      !@owner.is_a?(Business)
    end
  end
end
