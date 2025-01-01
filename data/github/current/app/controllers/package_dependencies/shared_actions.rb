# typed: true
# frozen_string_literal: true

# Actions shared between the global dependencies controller and the org-scoped
# dependencies controller
module PackageDependencies::SharedActions
  extend T::Helpers
  extend ActiveSupport::Concern
  include PlatformHelper
  include PackageDependencies::Licenses

  requires_ancestor { ApplicationController }

  PAGE_SIZE = 25

  # Maps user-friendly strings (published, updated) to sort enums we're expecting in Enums::RepositoryPackageReleaseOrderField
  # Ensure that any additions are added to Platform::Objects::RequestingUser#repository_package_releases
  #
  # Configuration for Sort dropdown and query parameters.
  #
  # The key should be the upcased first section of the value for the sort query, e.g. published-desc would map to PUBLISHED
  # Each value should be a hash containing:
  #   - enum - Sort enum defined in Enums::RepositoryPackageReleaseOrderField
  #   - queries - Array of queries which will be available in the sort dropdown on Packages#index
  #
  SORT_QUERY_CONFIG = {
    PUBLISHED: {
      enum: "PUBLISHED_ON",
      queries: [
        { query: "published-desc", label: "Newest" },
        { query: "published-asc", label: "Oldest" },
      ],
    },
    UPDATED: {
      enum: "UPDATED_AT",
      queries: [
        { query: "updated-desc", label: "Recently updated" },
        { query: "updated-asc", label: "Least recently updated" },
      ],
    },
    DEPENDENTS: {
      enum: "DEPENDENTS",
      queries: [
        { query: "dependents-desc", label: "Most dependents", default: true }, # If you'd like to change the default sort, remember to apply it in app/platform/objects/requesting_user.rb as well!
        { query: "dependents-asc", label: "Least dependents" },
      ],
    },
    VULNERABILITIES: {
      enum: "VULNERABILITIES",
      queries: [
        { query: "vulnerabilities-desc", label: "Most security advisories" },
        { query: "vulnerabilities-asc", label: "Least security advisories" },
      ],
    },
  }.freeze

  SEVERITIES = [:low, :moderate, :high, :critical].freeze

  def index_data(owner_ids)
    release_filter = graphql_pagination_params(page_size: PAGE_SIZE)
    release_filter[:owner_ids] = owner_ids
    release_filter[:package_manager] = ecosystem_in_query if ecosystem_in_query.present?
    release_filter[:package_name] = package_name_in_query if package_name_in_query.present?
    release_filter[:exact_match] = exact_package_name_match?
    release_filter[:package_version] = version_in_query if version_in_query.present?
    release_filter[:severity] = severity_in_query if severity_in_query.present?
    release_filter[:licenses] = license_enums_in_query if license_enums_in_query.present?
    release_filter[:only_vulnerable_packages] = vulnerable_in_query

    if sort_query_to_options.present?
      field = sort_query_to_options[:field]
      direction = sort_query_to_options[:direction]
      release_filter[:sort_by] = "NEWEST" if field == "PUBLISHED_ON" && direction == "DESC"
      release_filter[:sort_by] = "OLDEST" if field == "PUBLISHED_ON" && direction == "ASC"
      release_filter[:sort_by] = "RECENTLY_UPDATED" if field == "UPDATED_AT" && direction == "DESC"
      release_filter[:sort_by] = "LEAST_RECENTLY_UPDATED" if field == "UPDATED_AT" && direction == "ASC"
      release_filter[:sort_by] = "MOST_DEPENDENTS" if field == "DEPENDENTS" && direction == "DESC"
      release_filter[:sort_by] = "LEAST_DEPENDENTS" if field == "DEPENDENTS" && direction == "ASC"
      release_filter[:sort_by] = "MOST_VULNERABILITIES" if field == "VULNERABILITIES" && direction == "DESC"
      release_filter[:sort_by] = "LEAST_VULNERABILITIES" if field == "VULNERABILITIES" && direction == "ASC"
    else
      release_filter[:sort_by] = "MOST_DEPENDENTS"
    end

    result = Platform::Loaders::Dependencies.load_repository_package_releases(release_filter: release_filter).sync
    if result.ok?
      data = result.value!
      data[:page_info] = Platform::ConnectionWrappers::PageInfo.new(
        start_cursor: data[:page_info]["startCursor"],
        has_previous_page: data[:page_info]["hasPreviousPage"],
        has_next_page: data[:page_info]["hasNextPage"],
        end_cursor: data[:page_info]["endCursor"],
      )

      package_releases = data[:dependents].filter_map(&:package_release)
      repos = Set.new

      # Prefill repository/owners
      Platform::Security::RepositoryAccess.with_viewer(current_user) do
        Promise.all(package_releases.map do |package_release|
          package_release.async_repository.then do |repo|
            next unless repo
            repos.add(repo)
          end
        end).sync
      end

      # Prefill sponsors details on each repository
      if repos.present? && GitHub.sponsors_enabled?
        repos_list = repos.to_a
        GitHub::PrefillAssociations.prefill_batch_method(repos_list, :sponsorable_owner?)
        GitHub::PrefillAssociations.prefill_batch_method(repos_list, :owner_sponsored_by_viewer?, current_user)
      end
    else
      Failbot.report(result.error, app: "github-dependency-graph", rails_controller: "package_dependencies/shared_actions", owner_ids: owner_ids)
    end

    result
  end

  def render_package_dependencies_index(
    cap_filter:,
    owner_ids: nil,
    this_organization: nil,
    user_organizations: []
  )
    owner_ids = [this_organization.id] if this_organization.present?
    if owner_ids.present?
      result = index_data(owner_ids)
      if result.ok?
        data = result.value!
      else
        case result.error
        when ::DependencyGraph::Client::TimeoutError
          dependency_graph_timed_out = true
        when ::DependencyGraph::Client::ServiceUnavailableError, ::DependencyGraph::Client::ApiError, StandardError
          dependency_graph_unavailable = true
        end
      end
    end

    respond_to do |format|
      format.html do
        view = create_view_model(
          PackageDependencies::IndexView,
          parsed_query: parsed_query,
          raw_query: raw_query,
          enabled_orgs: user_organizations,
          this_organization: this_organization,
          queries_for_sort_dropdown: queries_for_sort_dropdown,
          dependency_graph_timed_out: dependency_graph_timed_out,
          dependency_graph_unavailable: dependency_graph_unavailable,
          licenses: LICENSES,
          cap_filter: cap_filter,
        )
        render "package_dependencies/index", locals: { data: data || {}, view: view }
      end
    end
  end

  def security_data(owner_ids)
    variables = {}
    variables[:owner_ids] = owner_ids
    variables[:package_manager] = ecosystem_in_query if ecosystem_in_query.present?
    variables[:package_name] = package_name_in_query if package_name_in_query.present?
    variables[:package_version] = version_in_query if version_in_query.present?
    variables[:licenses] = license_enums_in_query if license_enums_in_query.present?
    variables[:exact_match] = exact_package_name_match?

    Platform::Loaders::Dependencies.load_repository_package_release_vulnerabilities(release_filter: variables).sync
  rescue DependencyGraph::Client::ApiError => e
    Failbot.report(e, app: "github-dependency-graph", rails_controller: "package_dependencies/shared_actions", owner_ids: owner_ids)
  end

  def render_package_dependencies_security_graph(owner_ids: nil, this_organization: nil)
    view = PackageDependencies::IndexView.new(raw_query: raw_query, this_organization: this_organization)
    severities = Hash[SEVERITIES.collect { |severity| [severity, create_severity(severity, view)] }]

    owner_ids = [this_organization.id] if this_organization.present?
    if owner_ids.present?
      selected_severity = severity_in_query.to_s.to_sym
      security_data(owner_ids)&.each do |vuln|
        severity = vuln.severity.to_s.to_sym
        next unless severities.key?(severity)

        severities[severity][:count] = vuln.total_count
        severities[severity][:dependents] = vuln.dependents_count
        severities[severity][:selected] = selected_severity == severity
      end
    end

    respond_to do |format|
      format.json do
        render json: severities.values
      end
    end
  end

  def license_data(owner_ids)
    variables = {}
    variables[:owner_ids] = owner_ids
    variables[:package_manager] = ecosystem_in_query if ecosystem_in_query.present?
    variables[:package_name] = package_name_in_query if package_name_in_query.present?
    variables[:package_version] = version_in_query if version_in_query.present?
    variables[:severity] = severity_in_query if severity_in_query.present?
    variables[:only_vulnerable_packages] = vulnerable_in_query
    variables[:exact_match] = exact_package_name_match?

    Platform::Loaders::Dependencies.load_repository_package_release_licenses(release_filter: variables).sync
  rescue DependencyGraph::Client::ApiError => e
    Failbot.report(e, app: "github-dependency-graph", rails_controller: "package_dependencies/shared_actions", owner_ids: owner_ids)
  end

  def render_package_dependencies_licenses_graph(owner_ids: nil, this_organization: nil)
    owner_ids = [this_organization.id] if this_organization.present?
    licenses = license_data(owner_ids) if owner_ids.present?

    respond_to do |format|
      format.html do
        render partial: "package_dependencies/license_graph",
          locals: {
            licenses: licenses || [],
            view: create_view_model(PackageDependencies::IndexView,
              parsed_query: parsed_query,
              raw_query: raw_query,
              licenses: LICENSES,
              this_organization: this_organization,
              selected_licenses: licenses_in_query,
            )
          }
      end
    end
  end

  def render_package_dependencies_license_menu_content(this_organization: nil)
    render partial: "package_dependencies/filters/license_menu_content",
      locals: {
        view: create_view_model(PackageDependencies::IndexView,
          this_organization: this_organization,
          parsed_query: parsed_query,
          licenses: LICENSES,
        )
      }
  end

  private

  def package_manager
    params[:ecosystem]
  end

  def package_name
    Addressable::URI.unescape(params[:name])
  end

  def package_version
    Addressable::URI.unescape(params[:version])
  end

  def dependent_search
    params[:dependent_name]
  end

  def raw_query
    params[:query]
  end

  def parsed_query
    @parsed_query ||= Search::Queries::PackageDependenciesQuery.parse(params[:query])
  end

  def parsed_qualifiers
    @parsed_qualifiers ||= parsed_query.select do |component|
      # Select non-negated qualifiers such as qualifier:value
      component.is_a?(Array) && component.third != true
    end
  end

  def qualifier_values_in_query(qualifier)
    parsed_qualifiers.select do |component|
      component.first == qualifier
    end.map(&:second)
  end

  def first_qualifier_value_in_query(qualifier)
    qualifier_values_in_query(qualifier).first
  end

  def exact_package_name_match?
    first_qualifier_value_in_query(:name).present?
  end

  def package_name_in_query
    @package_name_in_query ||= first_qualifier_value_in_query(:name) || parsed_query.find { |component| component.is_a?(String) }
  end

  def sort_in_query
    return @sort_in_query if defined? @sort_in_query

    @sort_in_query = first_qualifier_value_in_query(:sort)
  end

  def ecosystem_in_query
    return @ecosystem_in_query if defined? @ecosystem_in_query

    ecosystem = first_qualifier_value_in_query(:ecosystem)
    @ecosystem_in_query = valid_ecosystem?(ecosystem) ? ecosystem : nil
  end

  def valid_ecosystem?(ecosystem)
    # checks if ecosystem passed for query is a valid one
    # Verifies this by checking AdvisoryDB ecosystems dictionary
    ecosystem.present? && AdvisoryDB::Ecosystems.dependency_graph_supported_names.map(&:downcase).include?(ecosystem.downcase)
  end

  def version_in_query
    return @version_in_query if defined? @version_in_query

    @version_in_query = first_qualifier_value_in_query(:version)
  end

  def valid_severity?(severity)
    SEVERITIES.include?(severity.to_s.to_sym)
  end

  def severity_in_query
    return @severity_in_query if defined? @severity_in_query

    severity = first_qualifier_value_in_query(:severity)
    @severity_in_query = valid_severity?(severity) ? severity : nil
  end

  def licenses_in_query
    return @licenses_in_query if defined? @licenses_in_query

    @licenses_in_query = qualifier_values_in_query(:license).select do |license|
      valid_license?(license)
    end.presence
  end

  def license_enums_in_query
    return @license_enums_in_query if defined? @license_enums_in_query

    @license_enums_in_query = licenses_in_query&.map do |license|
      license
        .gsub("+", "-PLUS")
        .gsub(/\A0/, "ZERO-")
        .parameterize
        .underscore
        .upcase
    end
  end

  def vulnerable_in_query
    return @vulnerable_in_query if defined? @vulnerable_in_query

    @vulnerable_in_query = parsed_qualifiers.any? do |component|
      component.first == :is && "vulnerable".casecmp?(component.second)
    end
  end

  def sort_query_to_options
    return @sort_query_to_options if defined? @sort_query_to_options

    @sort_query_to_options = begin
      # If there's no sort specified, use the default argument value
      return if sort_in_query.blank?

      field, direction = sort_in_query.split("-").map(&:upcase)
      enum_field = SORT_QUERY_CONFIG[field.to_sym][:enum]

      # If the field doesn't map to an enum or the direction isn't ASC/DESC, use default sort
      return if enum_field.nil? || !direction.in?(%w(ASC DESC))

      { field: enum_field, direction: direction.upcase }
    end
  end

  def queries_for_sort_dropdown
    @queries_for_sort_dropdown ||= SORT_QUERY_CONFIG.collect { |_, config| config[:queries] }.flatten
  end

  def add_qualifiers(qualifiers)
    query = parsed_query.dup
    query += qualifiers
    Search::Queries::PackageDependenciesQuery.stringify(query)
  end

  def create_severity(severity, view)
    query = add_qualifiers([[:is, "vulnerable"], [:severity, severity]])
    {
      label: severity.capitalize,
      count: 0,
      dependents: 0,
      url: view.build_path(query: query),
    }
  end
end
