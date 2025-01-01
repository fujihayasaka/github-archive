# typed: true
# frozen_string_literal: true

class Repos::DependabotAlertsController < AbstractRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:show]

  depends_on_clusters ApplicationRecord::RepositoriesPushes,
    only: [:show], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    ApplicationRecord::Iam,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index], optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Memex,
    only: [:update_error]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Memex,
    ApplicationRecord::Billing,
    only: [:update_logs]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:closed_as_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:ecosystem_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:exposure_analysis]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:manifest_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:network_redirect]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:package_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:severity_filter]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:filter_input_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Spokes,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:show_function_references]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:grouped_show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Billing,
    only: [:events]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Notify,
  ApplicationRecord::Mysql2,
  ApplicationRecord::IssuesPullRequests,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Configurations,
  ApplicationRecord::Billing,
    only: [:bot_resolve_status]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :index,
      :show,
      :show_function_references,
      :update_error,
      :update_logs,
      :manifest_filter,
      :package_filter,
      :ecosystem_filter,
      :severity_filter,
      :closed_as_filter,
      :filter_input_suggestions,
      :bot_resolve_status,
      :events,
      :grouped_show,
      :exposure_analysis,
      :network_redirect,
    ],
    optional: true

  preload_features [
    :dependency_graph_dgp_backed_npm_alerts
  ], only: [:index, :show]

  class RateLimitedError < StandardError; end
  include ControllerMethods::DependencySubmissionActions
  include GitHub::RateLimitable

  # rubocop:todo GitHub/MapToService
  map_to_service :dependabot, only: [:bot_resolve, :bot_resolve_status, :update_error, :update_logs]
  # rubocop:enable GitHub/MapToService

  before_action :require_user_can_manage_vulnerability_alerts, except: [:dismiss_one, :dismiss_many, :reopen, :reopen_many]
  before_action :require_dependabot, only: [:bot_resolve, :bot_resolve_status, :update_error, :update_logs]
  before_action :require_user_can_dismiss_vulnerability_alerts, only: [:dismiss_one, :dismiss_many, :reopen, :reopen_many]
  before_action :initialize_query, only: [:index, :closed_as_filter, :manifest_filter, :package_filter, :ecosystem_filter, :severity_filter]

  # allow us to render more than 100 pages of alerts
  skip_before_action :cap_pagination, only: :index, unless: :robot?

  rate_limit_requests except: :bot_resolve

  layout "repository"

  PACKAGE_FILTER_NAME = "package"
  SEVERITY_FILTER_NAME = "severity"
  ECOSYSTEM_FILTER_NAME = "ecosystem"
  MANIFEST_FILTER_NAME = "manifest"
  RESOLUTION_FILTER_NAME = "resolution"
  CVE_ID_FILTER_NAME = "cve_id"
  GHSA_ID_FILTER_NAME = "ghsa_id"
  EPSS_FILTER_NAME = "epss"
  STATE_CHANGE_COMMENT_MAX_LENGTH = 280

  def index
    # Track the time it takes to load the queried alerts, complete with
    # preloaded associations. The result of this method call is memoized.
    GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.query_time",
      tags: @query.datadog_tags
    ) do
      @query.alerts
    end

    view = create_view_model(
      RepositoryAlerts::IndexView,
      current_repository: current_repository,
      query_string: @query_string,
      query: @query,
      alerts: @query.alerts,
      alerts_page_path: method(:repository_alerts_path),
      filter_suggestions_path: method(:repository_alerts_filter_input_suggestions_path),
      menu_content_path: method(:menu_content_path),
    )

    async_mark_thread_as_read RepositoryDependabotAlertsThread.new(current_repository)

    GitHub.dogstats.distribution_time(
      "dependabot_alerts.index.render_time",
      tags: @query.datadog_tags
    ) do
      render "repos/dependabot_alerts/index", locals: { view: view }
    end
  end

  def show
    alert = current_repository.repository_vulnerability_alerts.
      without_default_scope. # Remove the "active" default scope
      find_by(number: params.require(:number))

    if alert&.active? && alert&.vulnerable_version_range.present?
      GitHub.dogstats.distribution_time("dependabot_alerts.show.render_time", tags: alert.datadog_tags) do
        render "repos/dependabot_alerts/show", locals: { alert: alert }
      end
    elsif alert&.withdrawn?
      flash[:error] = "The alert you requested (\##{alert.number}) has been withdrawn and is no longer available."
      redirect_to repository_alerts_path
    else
      render_404
    end
  end

  def show_function_references # rubocop:todo GitHub/UseRestfulActions
    alert = current_repository.repository_vulnerability_alerts.fixable.find_by(number: params.require(:number))

    if alert.nil?
      render_404
    else
      start_time = GitHub::Dogstats.monotonic_time
      function_references_per_file = alert.current_vulnerable_function_references
                                          .group_by(&:filename)
                                          .drop(params[:skip].to_i)

      if alert&.vulnerable_version_range.present?
        respond_to do |format|
          format.html do
            render "repos/dependabot_alerts/affected_files", locals: {
              current_repository: current_repository, function_references_per_file: function_references_per_file },
              layout: false
          end
        end
      end

      duration = GitHub::Dogstats.duration(start_time)
      tags = [
        "ghsa_id:#{alert.vulnerability.ghsa_id}",
        "affected_functions_count:#{alert.current_vulnerable_function_references.size}",
        "ecosystem:#{alert.vulnerable_version_range.ecosystem}",
      ]
      GitHub.dogstats.distribution("dependabot_exposure_analysis.show_function_references.render_time", duration, tags: tags)
    end
  end

  def grouped_show # rubocop:todo GitHub/UseRestfulActions
    query_string = "is:#{params[:state]} manifest:#{params[:manifest_path]} package:#{params[:package_name]}"
    redirect_to repository_alerts_path(q: query_string)
  end

  def update_error # rubocop:todo GitHub/UseRestfulActions
    dependency_update = fetch_dependency_update(params.require(:dependency_update_id))

    alert = current_repository.repository_vulnerability_alerts.find_by!(number: params.require(:number))

    view = create_view_model(
      RepositoryAlerts::UpdateErrorView,
      repository: current_repository,
      manifest_path: alert.vulnerable_manifest_path,
      package_name: alert.package_name,
      state: alert.alert_state,
      dependency_update: dependency_update,
    )

    if view.missing?
      render "repos/dependabot_alerts/missing_update_error", locals: { view: view }, status: :not_found
    else
      render "repos/dependabot_alerts/update_error", locals: { view: view }
    end
  end

  def update_logs # rubocop:todo GitHub/UseRestfulActions
    dependency_update = current_repository.dependency_updates.find_by(id: params.require(:dependency_update_id))

    alert = current_repository.repository_vulnerability_alerts.find_by!(number: params.require(:number))

    view = create_view_model(
      RepositoryAlerts::UpdateErrorView,
      repository: current_repository,
      manifest_path: alert.vulnerable_manifest_path,
      package_name: alert.package_name,
      state: alert.alert_state,
      dependency_update: dependency_update,
    )

    if view.missing?
      render "repos/dependabot_alerts/missing_update_error", locals: { view: view }, status: :not_found
    else
      check_run, update_job_logs, dependabot_unavailable, dependabot_error = nil

      begin
        response = Dependabot::Twirp.update_jobs_client.get_job_logs_by_github_request_id(
          repository_id: current_repository.id,
          github_request_id: dependency_update.id,
        )
        update_job_logs = response.update_job_logs
        update_job = response&.update_job
        if update_job&.actions_workflow_run_id&.nonzero?
          workflow_run = Actions::WorkflowRun.includes(:check_suite).find_by(
            id: update_job.actions_workflow_run_id,
            repository_id: current_repository.id,
          )
          check_suite = workflow_run&.check_suite
          check_run = check_suite&.latest_check_runs&.first
        elsif update_job&.actions_external_id.present?
          check_suite = current_repository.actions_check_suites.find_by(external_id: update_job.actions_external_id)
          check_run = check_suite&.latest_check_runs&.first
        end
      rescue Dependabot::Twirp::ServiceUnavailableError
        dependabot_unavailable = true
      rescue Dependabot::Twirp::Error => error
        dependabot_error = error
      end

      if check_run
        # Logs for jobs run on actions are viewable at the check run UI
        redirect_to check_run_path(id: check_run.id, check_suite_focus: true)
      else
        render "repos/dependabot_alerts/update_logs", locals: {
          view: view,
          update_job_logs: update_job_logs,
          dependabot_unavailable: dependabot_unavailable,
          dependabot_error: dependabot_error,
        }
      end
    end
  end

  def bot_resolve # rubocop:todo GitHub/UseRestfulActions
    alert = current_repository.repository_vulnerability_alerts.find_by!(number: params.require(:number))

    dependency_update = with_rate_limit(current_repository) do
      RepositoryDependencyUpdate.request_for_dependency(repository: current_repository,
                                                        manifest_path: alert.vulnerable_manifest_path,
                                                        package_name: alert.package_name,
                                                        trigger: :manual)
    end

    if dependency_update
      flash[:notice] = "Started generating a security update for #{alert.package_name}."
    else
      flash[:error] = "Failed to generate a security update for #{alert.package_name}. Try again later."
    end

    redirect_to repository_alert_path(number: alert.number)
  rescue RateLimitedError
    flash[:error] = "You've reached the maximum number of security updates at this time. Please try again later."

    redirect_to repository_alert_path(number: alert.number)
  end

  def bot_resolve_status # rubocop:todo GitHub/UseRestfulActions
    alert = current_repository.repository_vulnerability_alerts.find_by!(number: params.require(:number))
    component = DependabotAlerts::DependencyUpdateSummaryComponent.new(alert: alert)

    if component.show_pending_dependency_update?
      # Return 202 Accepted to signify that polling should continue
      head :accepted
    else
      render(component, layout: false) # rubocop:disable GitHub/RailsControllerRenderLiteral
    end
  end

  def closed_as_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterComponent.new(
      alerts_page_path: method(:repository_alerts_path),
      filter_type: RESOLUTION_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.resolution_filter_options,
      show_search_bar: false,
    ), layout: false
  end

  def manifest_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterItemListComponent.new(
      alerts_page_path: method(:repository_alerts_path),
      filter_type: MANIFEST_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.manifest_filter_options,
    ), layout: false
  end

  def package_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterItemListComponent.new(
      alerts_page_path: method(:repository_alerts_path),
      filter_type: PACKAGE_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.package_filter_options,
    ), layout: false
  end

  def ecosystem_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterItemListComponent.new(
      alerts_page_path: method(:repository_alerts_path),
      filter_type: ECOSYSTEM_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.ecosystem_filter_options,
    ), layout: false
  end

  def severity_filter # rubocop:todo GitHub/UseRestfulActions
    render DependabotAlerts::AlertFilterV2Component.new(
      alerts_page_path: method(:repository_alerts_path),
      filter_type: SEVERITY_FILTER_NAME,
      query_string: @query_string,
      item_list: @query.severity_filter_options,
    ), layout: false
  end

  def menu_content_path(path_args) # rubocop:todo GitHub/UseRestfulActions
    case path_args[:menu_content]
    when MANIFEST_FILTER_NAME
      repository_alerts_manifest_filter_path(path_args)
    when SEVERITY_FILTER_NAME
      repository_alerts_severity_filter_path(path_args)
    when PACKAGE_FILTER_NAME
      repository_alerts_package_filter_path(path_args)
    when ECOSYSTEM_FILTER_NAME
      repository_alerts_ecosystem_filter_path(path_args)
    when RESOLUTION_FILTER_NAME
      repository_alerts_closed_as_filter_path(path_args)
    else
      raise ArgumentError, "Unknown menu_content: #{path_args[:menu_content]}"
    end
  end

  def dismiss_one # rubocop:todo GitHub/UseRestfulActions
    number = params.require(:number)
    reason = params.require(:reason)
    comment = normalize_comment(params[:comment])

    if comment && (comment.length > STATE_CHANGE_COMMENT_MAX_LENGTH)
      head :bad_request
      return
    end

    alert = current_repository.repository_vulnerability_alerts.open.find_by!(number: number)

    alert.dismiss(actor: current_user, reason: reason, comment: comment)

    redirect_to repository_alert_path, notice: "Successfully dismissed alert."
  end

  def reopen # rubocop:todo GitHub/UseRestfulActions
    number = params.require(:number)

    alert = current_repository.repository_vulnerability_alerts.reopenable.find_by!(number: number)

    alert.reopen(actor: current_user)

    redirect_to repository_alert_path, notice: "Successfully reopened alert."
  end

  def reopen_many # rubocop:todo GitHub/UseRestfulActions
    ids = params.require(:ids)
    alerts = current_repository.repository_vulnerability_alerts.reopenable.where(id: ids)

    alerts_count = 0
    alerts.find_each do |alert|
      alert.reopen(actor: current_user)
      alerts_count += 1
    end

    redirect_to repository_alerts_path, notice: "Successfully reopened #{alerts_count} #{"alert".pluralize(alerts_count)}."
  end

  def dismiss_many # rubocop:todo GitHub/UseRestfulActions
    ids = params.require(:ids)
    reason = params.require(:reason)
    comment = normalize_comment(params[:comment])

    if comment && (comment.length > STATE_CHANGE_COMMENT_MAX_LENGTH)
      head :bad_request
      return
    end

    alerts = current_repository.repository_vulnerability_alerts.open.where(id: ids)

    alerts_count = 0
    alerts.find_each do |alert|
      alert.dismiss(actor: current_user, reason: reason, comment: comment)
      alerts_count += 1
    end

    redirect_to repository_alerts_path, notice: "Successfully dismissed #{alerts_count} #{"alert".pluralize(alerts_count)}."
  end

  def network_redirect # rubocop:todo GitHub/UseRestfulActions
    if alert_params.compact.empty?
      redirect_to repository_alerts_path(q: params[:q])
    elsif params[:update] == "update-errors"
      redirect_to repository_alert_update_errors_path(alert_params)
    elsif params[:update] == "update-logs"
      redirect_to repository_alert_update_logs_path(alert_params)
    else
      redirect_to grouped_repository_alert_path(alert_params)
    end
  end

  def exposure_analysis # rubocop:todo GitHub/UseRestfulActions
    alert = current_repository.repository_vulnerability_alerts.find(params.require(:id))
    range = alert.vulnerable_version_range
    affected_functions = range.affected_functions
    default_oid = current_repository.default_oid
    vulnerability = alert.vulnerability

    # Return an empty 304 (Not Modified) response if the there's no need to
    # recalculate the exposure analysis.
    return unless stale?(etag: "#{default_oid}\t#{affected_functions}", template: false)

    start_time = GitHub::Dogstats.monotonic_time
    aleph_response = GitHub::Aleph.find_references_to_qualified_names(
      repo: current_repository,
      commit_oid: default_oid,
      qualified_names: affected_functions,
    )
    duration = GitHub::Dogstats.duration(start_time)
    component = DependabotAlerts::ExposureAnalysisComponent.new(aleph_response: aleph_response)
    tags = [
      "ghsa_id:#{vulnerability.ghsa_id}",
      "vulnerable:#{component.vulnerable?}",
      "affected_functions:#{affected_functions.size}",
      "ecosystem:#{range.ecosystem}",
    ]
    GitHub.dogstats.distribution("dependabot_exposure_analysis.aleph_timing", duration, tags: tags)
    GitHub.dogstats.distribution("dependabot_exposure_analysis.aleph_location_count", component.location_count, tags: tags)

    render component, layout: false # rubocop:disable GitHub/RailsControllerRenderLiteral
  end

  def filter_input_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        render json: suggestions_for_filter(params[:suggestion]) || []
      end
    end
  end

  def events # rubocop:todo GitHub/UseRestfulActions
    alert = current_repository.repository_vulnerability_alerts.find_by!(number: params.require(:number))
    render DependabotAlerts::TimelineComponent.new(alert: alert, before: params.require(:before), after: params.require(:after)), layout: false
  end

  private

  def alert_params
    {
      manifest_path: params[:manifest_path],
      package_name: params[:package_name],
      state: params[:state],
    }
  end

  def fetch_dependency_update(dependency_update_id)
    if current_repository.dependabot_api_error_pages_enabled?
      dependency_update = current_repository.dependency_updates.find_by(id: dependency_update_id)
      Dependabot::UpdateJob.get_update_job(dependency_update)
    else
      current_repository.dependency_updates.find_by(id: dependency_update_id)
    end
  end

  def with_rate_limit(repository)
    # NOTE: Limit newly created accounts to curb abuse of automated manual
    # update requests.
    max_update_requests_per_1h = current_user.is_new? ? 300 : 3000
    rate_limit_key = "request-manual-dependabot-security-update:#{current_user.id}"
    if rate_limit_increment(rate_limit_key, max_tries: max_update_requests_per_1h, ttl: 1.hour).at_limit?
      GitHub.logger.info("Requested maximum number of manual security updates",
        "code.namespace": "Repos::DependabotAlertsController",
        "code.function": "bot_resolve",
        "enduser.id": current_user.login, # rubocop:disable GitHub/DoNotAllowLogin login is expected in logs
        "gh.dependabot.max_tries": max_update_requests_per_1h
      )

      raise RateLimitedError
    else
      yield
    end
  end

  def require_user_can_manage_vulnerability_alerts
    render_404 unless current_repository.can_view_vulnerability_alerts?(current_user)
  end

  def require_dependabot
    render_404 unless current_repository.automated_security_updates_visible_to?(current_user)
  end

  def require_user_can_dismiss_vulnerability_alerts
    render_404 unless current_repository.vulnerability_alerts_enabled? && current_repository.can_resolve_vulnerability_alerts?(current_user)
  end

  def initialize_query
    @query_string = params[:q].kind_of?(String) ? params[:q].strip : Search::Queries::SecurityCenter::DependabotAlertsQuery::DEFAULT_QUERY

    query_hash = Search::Queries::SecurityCenter::DependabotAlertsQuery.parse_and_normalize(
      @query_string,
      allow_epss_percentage: allow_epss_dependabot_ui?,
      can_sort_by_most_important: true
    )

    @query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(
      allow_epss_percentage: allow_epss_dependabot_ui?,
      repository: current_repository,
      sort: :most_important,
    ).
      paginate(params[:page]).
      state_is(query_hash[:is]).
      resolutions_are(query_hash[:resolution]).resolutions_are_not(query_hash[:"-resolution"]).
      severities_are(query_hash[:severity]).severities_are_not(query_hash[:"-severity"]).
      manifests_are(query_hash[:manifest]).manifests_are_not(query_hash[:"-manifest"]).
      packages_are(query_hash[:package]).packages_are_not(query_hash[:"-package"]).
      ecosystems_are(query_hash[:ecosystem]).ecosystems_are_not(query_hash[:"-ecosystem"]).
      dependency_scopes_are(query_hash[:scope]).negated_dependency_scopes_are(query_hash[:"-scope"]).
      dependency_relationships_are(query_hash[:relationship]).negated_dependency_relationships_are(query_hash[:"-relationship"]).
      has_a(query_hash[:has]).has_none(query_hash[:"-has"]).
      search(query_hash[:phrase]).
      sort_by(query_hash[:sort]).
      # It's ok to pass EPSS qualifiers in indiscriminately; the query will ignore it if it's not allowed
      epss_percentages_are(query_hash[:epss_percentage]).epss_percentages_are_not(query_hash[:"-epss_percentage"])
  end

  def suggestions_for_filter(filter_name = "")
    new_query = RepositoryVulnerabilityAlert::UngroupedAlertQuery.new(repository: current_repository)
    case filter_name
    when PACKAGE_FILTER_NAME
      new_query.package_filter_options.map { |package| { value: package[:label] } }.compact
    when ECOSYSTEM_FILTER_NAME
      new_query.ecosystem_filter_options.map { |ecosystem| { value: ecosystem[:label] } }.compact
    when MANIFEST_FILTER_NAME
      new_query.manifest_filter_options.map { |manifest| { value: manifest[:label] } }.compact
    when CVE_ID_FILTER_NAME
      new_query.cve_id_filter_options.map { |cve| { value: cve } }.compact
    when GHSA_ID_FILTER_NAME
      new_query.ghsa_id_filter_options.map { |ghsa| { value: ghsa } }.compact
    when EPSS_FILTER_NAME
      if allow_epss_dependabot_ui?
        [{ value: "percentage>=" }, { value: "percentage>" }, { value: "percentage<" }, { value: "percentage<=" }]
      else
        []
      end
    else
      []
    end
  end

  def normalize_comment(comment)
    return nil if comment.nil? || comment.empty?
    comment.encode("UTF-8", universal_newline: true)
  end

  def allow_epss_dependabot_ui?
    current_repository.feature_enabled?(:advisory_db_epss_dependabot_ui)
  end
end
