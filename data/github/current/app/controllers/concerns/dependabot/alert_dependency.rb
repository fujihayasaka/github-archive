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

    abstract!
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
    # Tabs split into :dependabot_malware / :dependabot_vulnerabilities.
    def selected_tab_for_security_center(scope)
      if malware_route?
        :dependabot_malware
      else
        :dependabot_vulnerabilities
      end
    end

    sig { returns(T.untyped) }
    def es_query_params
      {
        phrase: es_query_phrase,
        scope: search_scope,
        aggregations: true,
        current_user:,
        cap_filter:,
      }
    end

    sig { abstract.returns(RepositoryVulnerabilityAlert::UngroupedAlertQuery) }
    private def query; end

    def search_scope
      case self
      when Businesses::BusinessController
        this_business
      when Orgs::Controller
        this_organization
      when AbstractRepositoryController
        current_repository
      else
        raise "Unknown controller type for search scope"
      end
    end

    # The select panel filter we're using sends the filter query
    # for remote filtering in the "q" param, so on these calls
    # the "search_q" param contains the user's actual search query.
    # This function coerces the "q" parameter back into its expected
    # place.
    def fix_filter_query_params
      extracted_params = params.extract!(:q, :search_q)
      params[:q] = extracted_params[:search_q]
      params[:filter] = extracted_params[:q]
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def repository_name_filter_options
      return query.repository_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:repository_name, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |repo_name, count|
        {
          label: repo_name,
          count: count,
          slug: repo_name
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def organization_filter_options
      return query.organization_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:owner_login, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |owner_login, count|
        {
          label: owner_login,
          count: count,
          slug: owner_login
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def repository_nwo_filter_options
      return query.repository_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:repository_nwo, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |repo_nwo, count|
        org_login, repo_name = repo_nwo.split("/")
        {
          label: repo_name,
          count: count,
          description: org_login,
          slug: repo_nwo,
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def package_filter_options
      return query.package_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:package_name, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |package_name, count|
        {
          label: package_name,
          count: count,
          slug: package_name
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def ecosystem_filter_options
      return query.ecosystem_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:ecosystem, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |ecosystem, count|
        ecosystem_label = AdvisoryDB::Ecosystems.label(ecosystem)
        {
          label: ecosystem_label,
          count: count,
          slug: ecosystem_label
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def resolution_filter_options
      return query.resolution_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:resolution, nil, **es_query_params)
      resolution_counts = es_query.filter_option_counts
      RepositoryVulnerabilityAlert::RESOLUTION_OPTIONS.map do |option|
        count = resolution_counts.find { |r, _| r == option[:slug].underscore }&.last || 0
        {
          state: option[:state],
          count: count,
          label: option[:label],
          slug: option[:slug]
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def severity_filter_options
      return query.severity_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:severity, nil, **es_query_params)
      severity_counts = es_query.filter_option_counts
      Vulnerability::SEVERITIES.reverse.map do |severity|
        count = severity_counts.find { |s, _| s == severity }&.last || 0
        {
          label: severity.capitalize,
          count: count,
          slug: severity
        }
      end
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def manifest_filter_options
      return query.manifest_filter_options unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:"manifest_path.keyword", params[:filter], **es_query_params)
      manifest_counts = es_query.filter_option_counts
      manifest_counts.map do |path, count|
        # preserve case for manifest path
        {
          label: path,
          count: count,
          slug: path
        }
      end
    end

    def cve_id_filter_options
      return query.cve_id_filter_options.filter_map { |cve| { label: cve } } unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:cve_id, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |cve_id, count|
        {
          label: cve_id,
          count: count,
          slug: cve_id
        }
      end
    end

    def ghsa_id_filter_options
      return query.ghsa_id_filter_options.filter_map { |ghsa| { label: ghsa } } unless GitHub.dependabot_es_search_enabled?

      es_query = Search::Queries::DependabotAlertsFilterQuery.new(:ghsa_id, params[:filter], **es_query_params)
      es_query.filter_option_counts.map do |ghsa_id, count|
        {
          label: ghsa_id,
          count: count,
          slug: ghsa_id
        }
      end
    end
  end
end
