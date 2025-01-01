# typed: true
# frozen_string_literal: true

class NetworkController < GitContentController
  include ControllerMethods::DependencySubmissionActions

  skip_before_action :try_to_expand_path
  before_action :dependency_graphs_enabled?, only: [:dependents, :dependencies]
  before_action :enforce_plan_supports_insights, only: :show
  skip_before_action :cap_pagination, only: :dependencies, unless: :robot?
  layout "repository"

  stylesheet_bundle :insights

  # rubocop:todo GitHub/MapToService
  map_to_service :dependency_graph, only: [:dependencies, :dependents]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::Notify,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:dependencies]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    only: [:members]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:dependents]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show, :dependencies, :dependents, :members],
    optional: true

  DEPENDENTS_PER_PAGE = 30

  def members # rubocop:todo GitHub/UseRestfulActions
    view = create_view_model(Networks::MembersView, network: current_repository.network)
    render "network/members", locals: { view: view }
  end

  def dependents # rubocop:todo GitHub/UseRestfulActions
    dependent_type = params[:dependent_type] || default_dependent_type
    return render_404 if current_repository.private? || !is_dependent_type_valid?(dependent_type)

    owner_filter = if params[:owner]
      User.find_by_login(params[:owner])
    end

    packages = load_packages
    package_id = params[:package_id] || current_repository.used_by_package_id
    package = load_package_with_dependents(dependent_type, owner_id: owner_filter&.id, package_id: package_id)
    dependents_unavailable = !package.ok? || !packages.ok?

    respond_to do |format|
      format.html do
        render "network/dependents", locals: {
          package:                package.value { nil },
          packages:               packages.value { [] },
          dependent_type:         dependent_type,
          dependents_unavailable: dependents_unavailable,
          package_id:             package_id,
          owner_filter:           owner_filter,
        }
      end
    end
  end

  def dependencies # rubocop:todo GitHub/UseRestfulActions
    # until pagination arrives we are displaying everything
    # available
    @manifests_per_page = 1000
    @dependencies_per_page = 1000
    @dependencies_first_page = @dependencies_per_page

    page = params.fetch(:page, 1).to_i
    provider = DependencyGraph::RepositoryDependenciesProvider.new
    per_page = 20

    dependabot_alerts = if can_view_alerts?
      current_repository
        .repository_vulnerability_alerts
        .has_vulnerable_version_range
        .open
        .preload(:vulnerability, :vulnerable_version_range)
        .map do |alert|
          {
            vulnerable_manifest_path: alert.vulnerable_manifest_path,
            vulnerable_version_range_affects: alert.vulnerable_version_range.affects,
            vulnerable_requirements: alert.vulnerable_requirements,
            vulnerability_severity: severity_to_proto(alert.vulnerability.severity),
            vulnerable_version_range_id: alert.vulnerable_version_range.id,
            vulnerable_version_range_requirements: alert.vulnerable_version_range.requirements,
          }
        end
    else
      []
    end

    request = begin
      provider.search_dependencies_for_repository(
        repository_id: current_repository.id,
        page: page,
        per_page: per_page,
        query: query_builder.search_query,
        dependabot_alerts:  dependabot_alerts,
        preview_enabled: user_or_global_feature_enabled?(:dependency_graph_preview),
        relationship_filter: relationship_to_proto(query_builder.relationship),
        ecosystem_filter: ecosystem_to_proto(query_builder.ecosystem),
      )
    rescue Faraday::ConnectionFailed, DependencyGraph::BaseTwirpClient::Error => error
      Failbot.report(error, app: "github-dependency-graph")
      render "network/dependencies/error", {}
      return
    end

    repository_ids = request[:response].results.map(&:repository_id)
    repositories_by_id = Repository
      .public_scope
      .where(id: repository_ids)
      .select(:id, :owner_login, :name)
      .map { |repo| [repo.id, repo] }
      .to_h

    alerts = {}
    if can_view_alerts?
      request[:response].results.each do |result|
        alerts[result] = current_repository.applicable_vulnerability_alerts(
          manifest_path: result.manifest_path,
          package_name: result.package_name,
          requirements: result.requirements,
          vulnerable_version_range_ids: result.respond_to?(:vulnerable_version_range_ids) ? result.vulnerable_version_range_ids.to_a : []
        )
      end
    end

    results = WillPaginate::Collection.create(page, per_page, request[:response].total_results) do |pager|
      pager.replace(request[:response].results)
    end

    does_results_have_root_ancestors = results.any? do |result|
      result.root_ancestors && result.root_ancestors.length > 0
    end

    respond_to do |format|
      format.html do
        render "network/dependencies/index", locals: {
          results: results,
          repository_has_snapshots: request[:response].repository_has_snapshots,
          repositories_by_id: repositories_by_id,
          alerts: alerts,
          user: current_user,
          commit: current_commit,
          query: query_builder.raw_query,
          query_builder: query_builder,
          package_managers: request[:response].package_managers,
          does_results_have_root_ancestors: does_results_have_root_ancestors
        }
      end
    end
  end

  def show
    check_update_network_graph
    render "network/show"
  end

  def meta # rubocop:todo GitHub/UseRestfulActions
    # Clients can poll every 10s.
    expires_in 10.seconds

    if network_graph.current?
      render json: network_graph.meta_json
    else
      check_update_network_graph
      head 202
    end
  end

  def chunk # rubocop:todo GitHub/UseRestfulActions
    # Clients can poll every 10s.
    expires_in 10.seconds

    start_time = params[:start] ? params[:start].to_i : nil
    end_time   = params[:end] ? params[:end].to_i : nil
    if network_graph.current?
      render json: (network_graph.data_json(start_time, end_time))
    else
      check_update_network_graph
      render json: {}
    end
  end

  private

  memoize def query_builder
    return @query_builder if defined?(@query_builder)
    @query_builder ||= Search::Queries::DependencyGraph::SearchQueryBuilder.new(
      query: params[:q]
    )
  end

  def severity_to_proto(severity_str)
    case severity_str
    when "low"
      :SEVERITY_LOW
    when "moderate"
      :SEVERITY_MODERATE
    when "high"
      :SEVERITY_HIGH
    when "critical"
      :SEVERITY_CRITICAL
    end
  end

  def relationship_to_proto(relationship)
    return nil if relationship.nil? || relationship.empty?

    case relationship
    when "direct"
      DependencyGraphAPI::V1::Relationship::RELATIONSHIP_DIRECT
    when "transitive"
      DependencyGraphAPI::V1::Relationship::RELATIONSHIP_INDIRECT
    when "inconclusive"
      DependencyGraphAPI::V1::Relationship::RELATIONSHIP_INCONCLUSIVE
    else
      DependencyGraphAPI::V1::Relationship::RELATIONSHIP_UNKNOWN
    end
  end

  sig { params(ecosystem: T.nilable(String)).returns(T::Array[T.nilable(Integer)]) }
  def ecosystem_to_proto(ecosystem)
    return [] if ecosystem.nil? || ecosystem.empty?

    symbol = DependencyGraph::Ecosystems.label_to_symbol(ecosystem)
    symbol ? [DependencyGraphAPI::V1::PackageManager.resolve(symbol)] : []
  end

  def can_view_alerts?
    logged_in? && current_repository.vulnerability_alerts_visible_to?(current_user)
  end

  def dependency_graphs_enabled?
    render_404 unless GitHub.dependency_graph_enabled?
    GitHub.context.push(is_public: current_repository.public?)
    Audit.context.push(is_public: current_repository.public?)
  end

  def default_dependent_type
    PlatformTypes::DependencyGraphDependentType::REPOSITORY
  end

  memoize def network_graph
    current_repository.network_graph
  end
  helper_method :network_graph

  def check_update_network_graph
    # Avoid an expensive network graph update for crawlers.
    return if robot?
    graph = current_repository.network_graph
    graph.build
  end

  def enforce_plan_supports_insights
    return if current_repository.plan_supports?(:insights)
    redirect_to forks_path(current_repository.owner, current_repository)
  end

  def is_dependent_type_valid?(dependent_type)
    Platform::Enums::DependencyGraphDependentType.values.map { |x| x[0] }.include? dependent_type
  end

  def load_package_with_dependents(dependent_type, owner_id: nil, package_id:)
    dependents_filter = dependents_filter_for(dependent_type, owner_id: owner_id)
    result = Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: current_repository.id,
        first: 1,
        package_id: package_id,
        preview: current_repository.dependency_graph_preview?,
      },
      dependents_filter: dependents_filter,
      include_dependents: true,
    }).sync

    result.value!.first&.load_dependent_repositories(current_user) if result.ok?
    result.map { |packages| packages.first }
  end

  def dependents_filter_for(dependent_type, owner_id: nil)
    filter = { type: dependent_type.to_s.downcase.to_sym }

    if params[:dependents_before]
      filter[:before] = params[:dependents_before]
      filter[:last] = DEPENDENTS_PER_PAGE
    else
      filter[:after] = params[:dependents_after]
      filter[:first] = DEPENDENTS_PER_PAGE
    end

    filter[:owner_id] = owner_id if owner_id
    filter
  end

  def load_packages
    Platform::Loaders::Dependencies.load_packages({
      package_filter: {
        repository_id: current_repository.id,
        first: 100,
        preview: current_repository.dependency_graph_preview?,
      }
    }).sync
  end
end
