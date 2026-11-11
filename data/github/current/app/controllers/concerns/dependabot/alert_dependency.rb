# typed: true
# frozen_string_literal: true

module Dependabot
  module AlertDependency
    extend T::Helpers
    include GitHub::Memoizer
    include DependabotAlertsSavedView

    REPO_FILTER_NAME = "repo"
    SEVERITY_FILTER_NAME = "severity"
    PACKAGE_FILTER_NAME = "package"
    ECOSYSTEM_FILTER_NAME = "ecosystem"
    MANIFEST_FILTER_NAME = "manifest"
    RESOLUTION_FILTER_NAME = "resolution"
    CVE_ID_FILTER_NAME = "cve_id"
    GHSA_ID_FILTER_NAME = "ghsa_id"
    EPSS_FILTER_NAME = "epss"
    ARTIFACT_REGISTRY_URL_FILTER_NAME = "artifact_registry_url"
    STATE_CHANGE_COMMENT_MAX_LENGTH = 280

    requires_ancestor { ApplicationController }

    def normalize_comment(comment)
      return nil if comment.nil? || comment.empty?
      comment.encode("UTF-8", universal_newline: true)
    end

    # Prefill all associations required to render individual rows without N+1 queries.
    def prefill_associations_for_ui(alerts)
      GitHub::PrefillAssociations.prefill_associations(alerts, [
        { repository: [:owner, :internal_repository] },
        :vulnerability,
        :vulnerable_version_range,
        { repository_dependency_updates: { pull_request: { repository: :owner } } },
        :assignees,
      ])
    end

    memoize def query_string
      # If no query parameter is provided and the feature is enabled, try to load the user's saved view
      if params[:q].nil? && current_user&.feature_flag_enabled?(:dependabot_alerts_saved_view_enabled, default: false)
        load_saved_view_for_user || Search::Queries::SecurityCenter::DependabotAlertsQuery.default_query(current_user)
      else
        params[:q].kind_of?(String) ? params[:q].strip : Search::Queries::SecurityCenter::DependabotAlertsQuery.default_query
      end
    end

    # Returns the ES phrase with the appropriate classification type filter
    # appended internally. This keeps the type qualifier out of the
    # user-visible query string.
    #
    # On malware routes, appends "classification:malware" to restrict to malware.
    # On non-malware routes, appends "-classification:malware" to exclude malware.
    def es_query_phrase
      if malware_route?
        query_string + " classification:malware"
      else
        query_string + " -classification:malware"
      end
    end

    # Returns true if the current request is for a malware-specific route.
    def malware_route?
      params[:malware].present?
    end

    # Returns the selected_tab value for the security nav sidebar.
    # When the malware FF is on, tabs split into :dependabot_malware / :dependabot_vulnerabilities.
    # When it's off, there's a single :dependabot_alerts tab.
    def selected_tab_for_security_center(scope)
      if malware_route?
        :dependabot_malware
      elsif FeatureFlag.vexi.enabled?("dependabot_allow_malware_frontend", current_user, scope, default: false)
        :dependabot_vulnerabilities
      else
        :dependabot_alerts
      end
    end
  end
end
