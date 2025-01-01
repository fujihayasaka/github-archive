# typed: true
# frozen_string_literal: true

class PackageDependencies::GlobalController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests
  include PackageDependencies::SharedActions

  # needs investigation for protected organization access
  skip_before_action :perform_conditional_access_checks, only: [:index, :show, :security_graph, :licenses_graph, :license_menu_content] # rubocop:todo GitHub/DoNotSkipCapBeforeAction
  before_action  :login_required
  before_action :require_enabled_org, only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Billing,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:license_menu_content]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:licenses_graph]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    only: [:security_graph]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show], optional: true

  PACKAGE_PAGE_TABS = [:description, :dependencies, :contributors, :security, :dependents].freeze

  stylesheet_bundle :insights

  def index
    render_package_dependencies_index(
      cap_filter: cap_filter,
      owner_ids: selected_org_ids,
      user_organizations: enabled_user_organizations,
    )
  end

  def show
    unless selected_org_ids.empty?
      package_release = load_package_release
      dependency_graph_timed_out = dependency_graph_timed_out?(package_release.error) unless package_release.ok?
      dependency_graph_unavailable = dependency_graph_unavailable?(package_release.error) unless package_release.ok?
      package_release = package_release.value { nil }

      unless dependency_graph_timed_out || dependency_graph_unavailable
        recent_releases = load_recent_releases
        dependency_graph_timed_out ||= dependency_graph_timed_out?(recent_releases.error) unless recent_releases.ok?
        dependency_graph_unavailable ||= dependency_graph_unavailable?(recent_releases.error) unless recent_releases.ok?
        recent_releases = recent_releases.value { [] }
      end

      unless dependency_graph_timed_out || dependency_graph_unavailable
        repository_package_release = load_repository_package_release
        dependency_graph_timed_out ||= dependency_graph_timed_out?(repository_package_release.error) unless repository_package_release.ok?
        dependency_graph_unavailable ||= dependency_graph_unavailable?(repository_package_release.error) unless repository_package_release.ok?
        repository_package_release = repository_package_release.value { nil }
        prefill_repositories(repository_package_release&.dependents) if selected_tab == :dependents
      end

      unless dependency_graph_timed_out || dependency_graph_unavailable
        return render_404 unless package_release.present? && repository_package_release.present?
      end
    end

    repository = Platform::Security::RepositoryAccess.with_viewer(current_user) do
      package_release&.repository
    end

    if package_release && repository_package_release
      tab_data = load_selected_tab_data(package_release, repository)
      if tab_data
        dependency_graph_timed_out = dependency_graph_timed_out?(tab_data)
        dependency_graph_unavailable = dependency_graph_unavailable?(tab_data)
      end
    end

    respond_to do |format|
      format.html do
        view = create_view_model(
          PackageDependencies::ShowView,
          parsed_query: parsed_query,
          raw_query: raw_query,
          selected_tab: selected_tab,
          enabled_orgs: enabled_user_organizations,
          selected_org_ids: selected_org_ids,
          package_name: package_name,
          package_version: package_version,
          package_manager: package_manager,
          dependent_search: dependent_search,
          repository: repository,
          dependency_graph_timed_out: dependency_graph_timed_out,
          dependency_graph_unavailable: dependency_graph_unavailable,
          cap_filter: cap_filter,
          unauthorized_organizations: enabled_unauthorized_organizations,
        )
        render "package_dependencies/show", locals: {
          package_release: package_release,
          repository_package_release: repository_package_release,
          recent_releases: recent_releases,
          vulnerabilities_count: repository_package_release&.vulnerabilities_count || 0,
          selected_tab_data: tab_data || nil,
          view: view,
          name_with_display_owner: package_release&.repository&.name_with_display_owner,
        }
      end
    end
  end

  def load_selected_tab_data(package_release, repository) # rubocop:todo GitHub/UseRestfulActions
    case selected_tab
    when :description
      description_data(repository) if repository.present?
    when :dependencies
      dependencies_data(repository) if repository.present?
    when :security
      security_vulnerabilities_data
    end
  end

  def security_graph # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_security_graph(owner_ids: selected_org_ids)
  end

  def licenses_graph # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_licenses_graph(owner_ids: selected_org_ids)
  end

  def license_menu_content # rubocop:todo GitHub/UseRestfulActions
    render_package_dependencies_license_menu_content
  end

  private

  def dependencies_data(repository)
    result = Platform::Loaders::Dependencies.load_manifests(repository, {
      manifest_filter: {
        repository_id: repository.id,
        first: 5,
        with_dependencies: false,
        preview: repository.dependency_graph_preview?,
        package_manager: package_manager,
        package_name: package_name,
      },
      include_dependencies: true,
      dependencies_filter: { first: PAGE_SIZE },
    }).sync

    if result.ok?
      manifests = result.value![:manifests]
      prefill_repositories(manifests.flat_map(&:dependencies))

      manifests
    else
      result.error
    end
  end

  def description_data(repository)
    result = Platform::Loaders::Dependencies.load_manifests(repository, {
      manifest_filter: {
        repository_id: repository.id,
        first: 1,
        with_dependencies: false,
        preview: repository.dependency_graph_preview?,
        package_name: package_name,
        package_manager: package_manager,
      },
      include_dependencies: false,
    }).sync

    result.ok? ? result.value![:manifests]&.first&.filename : result.error
  end

  def security_vulnerabilities_data
    filter = {
      package_name: package_name,
      package_manager: package_manager,
      contains_version: package_version,
    }
    result = Platform::Loaders::Dependencies.load_package_release_vulnerabilities(vulnerabilities_filter: filter).sync
    if result.ok?
      SecurityVulnerability.disclosed.includes(:security_advisory).where(id: result.value!)
    else
      result.error
    end
  end

  def require_enabled_org
    render_404 if enabled_user_organizations.empty? &&
      enabled_unauthorized_organizations.empty?
  end

  def selected_tab # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @selected_tab ||= PACKAGE_PAGE_TABS.include?(params[:tab].to_s.to_sym) ? params[:tab].to_sym : :description
  end

  def selected_org_ids # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @selected_org_ids ||= enabled_user_organizations.select do |org|
      orgs_in_query.empty? || orgs_in_query.any? { |value| org.display_login.casecmp?(value) }
    end.map(&:id)
  end

  def orgs_in_query
    qualifier_values_in_query(:org)
  end

  def enabled_unauthorized_organizations # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @enabled_unauthorized_organizations ||= cap_filter.unauthorized_resources(current_user.organizations).select do |org|
      org.dependency_insights_enabled_for?(current_user)
    end
  end

  def enabled_user_organizations # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @enabled_orgs if defined?(@enabled_orgs)
    authorized_orgs = cap_filter.authorized_resources(current_user.organizations)
    @enabled_orgs = authorized_orgs.keep_if { |org| org.dependency_insights_enabled_for?(current_user) }
  end

  def graphql_errors(data)
    if errors = data.try(:errors)
      errors.all.messages.values.flatten
    else
      []
    end
  end

  def dependency_graph_timed_out?(data)
    data.is_a?(DependencyGraph::Client::TimeoutError) || graphql_errors(data).include?("timedout")
  end

  def dependency_graph_unavailable?(data)
    data.is_a?(DependencyGraph::Client::ApiError) || graphql_errors(data).include?("unavailable")
  end

  def load_package_release
    result = Platform::Loaders::Dependencies.load_package_releases(
      release_filter: {
        first: 1,
        package_name: package_name,
        package_manager: package_manager,
        requirements: "= #{package_version}",
        default_to_latest: false,
        include_unpublished: true,
        preview: true,
      },
      dependencies_filter: nil,
      include_dependencies: false,
    ).sync

    Failbot.report(result.error, app: "github-dependency-graph") unless result.ok?

    result.map { |releases| releases.first }
  end

  def load_recent_releases
    result = Platform::Loaders::Dependencies.load_package_releases(
      release_filter: {
        first: 3,
        package_name: package_name,
        package_manager: package_manager,
        default_to_latest: true,
        include_unpublished: false,
        preview: true,
      },
      dependencies_filter: nil,
      include_dependencies: false,
    ).sync

    Failbot.report(result.error, app: "github-dependency-graph") unless result.ok?

    result
  end

  def load_repository_package_release
    release_filter = {
      first: 1,
      package_name: package_name,
      package_manager: package_manager,
      package_version: package_version,
      owner_ids: selected_org_ids,
      exact_match: true,
    }

    dependents_filter = { owner_ids: selected_org_ids, dependent_name: dependent_search }
    if selected_tab == :dependents
      dependents_filter = dependents_filter.merge(graphql_pagination_params(page_size: PAGE_SIZE))
    end

    result = Platform::Loaders::Dependencies.load_repository_package_releases(
      release_filter: release_filter,
      dependents_filter: dependents_filter,
      include_dependent_version_counts: true,
    ).sync

    Failbot.report(result.error, app: "github-dependency-graph") unless result.ok?

    result.map { |releases| releases[:dependents].first }
  end

  def prefill_repositories(models)
    models = models&.compact
    return unless models.present?

    # Prefill repository/owners on each dependency
    Platform::Security::RepositoryAccess.with_viewer(current_user) do
      Promise.all(models.map do |model|
        model.async_repository.then { |repo| repo&.async_owner }
      end).sync
    end
  end
end
