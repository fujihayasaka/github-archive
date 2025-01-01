# typed: true
# frozen_string_literal: true

module Settings
  class SecurityAnalysisFormComponent < ApplicationComponent
    include SecurityAnalysisSettingsHelper

    attr_reader :private_repo_count, :public_repo_count, :repo_count

    def initialize(owner:, public_repo_count:, repo_count:, cursor:, custom_patterns_query: "", actor: nil)
      @owner = owner
      @private_repo_count = repo_count - public_repo_count
      @public_repo_count = public_repo_count
      @repo_count = repo_count
      @cursor = cursor
      @custom_patterns_query = custom_patterns_query
      @actor = actor
    end

    def ghas_settings_path
      return settings_security_analysis_ghas_settings_enterprise_path(slug: @owner) if @owner.is_a?(Business)

      settings_org_security_analysis_ghas_settings_path(
        @owner,
        cursor: @cursor,
        custom_patterns_query: @custom_patterns_query,
        tip: params[:tip],
      )
    end

    private

    # variance in the blocking-enablement-warning tag based on if org or business
    def location_settings_tag
      @owner.is_a?(Business) ? "location:business_settings" : "location:org_settings"
    end

    # Dependency graph enablement settings shouln't be currently
    # available at the business/enterprise level
    memoize def show_dependency_graph_settings?
      !@owner.is_a?(Business)
    end

    # Dependabot updates enablement settings shouln't be currently
    # available at the business/enterprise level on GHES/GHEC
    memoize def show_dependabot_updates_settings?
      !@owner.is_a?(Business)
    end

    memoize def show_private_vulnerability_reporting_settings?
      !@owner.is_a?(Business) &&
      GitHub.private_vulnerability_reporting_enabled?
    end

    def security_configurations_enabled?
      @owner.security_configurations_enabled?
    end

    def org_admin?
      @owner.is_a?(User) ? @owner.adminable_by?(@actor) : false
    end
  end
end
