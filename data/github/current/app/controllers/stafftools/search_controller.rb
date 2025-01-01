# typed: true
# frozen_string_literal: true

class Stafftools::SearchController < StafftoolsController
  include AuditLogAsyncQueryHelper

  javascript_bundle :"audit-log-stafftools-async"

  PER_PAGE = 50

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    only: [:audit_log]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    only: [:async_query_status]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    only: [:async_query_results]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql5,
    only: [:actions_workflow_execution]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:search, :search_results_async]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    only: [:user_assets]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    only: [:repository_files]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    only: [:cname]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:audit_log_advanced_search]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:search, :search_results_async, :actions_workflow_execution, :audit_log],
    optional: true

  def search # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        searcher = ::Stafftools::Searcher.new(params[:query], current_user)

        if searcher.query.blank?
          return redirect_to stafftools_path
        end

        if current_user.feature_enabled?(:stafftools_async_search_results)
          render "stafftools/search/search", locals: { query: searcher.query } unless performed?
          return
        end

        if app = searcher.search_for_oauth_application_by_key.results.oauth_application
          return redirect_to stafftools_user_application_path(app.user, app.id)
        end

        if app = searcher.search_for_integration_by_key.results.integration
          return redirect_to gh_stafftools_app_path(app.user, app.slug)
        end

        if access = searcher.search_for_oauth_access_token.results.oauth_access
          return redirect_to stafftools_user_oauth_token_path(access.user, access.id)
        end

        if key = searcher.search_for_public_key.results.public_key
          if key.repository
            # Found a deploy key.
            redirect_to gh_stafftools_repository_path(key.repository)
          else
            redirect_to stafftools_user_path(key.user)
          end

          # Return to stop execution and prevent ElasticSearch errors searching
          # for something that looks like a key fingerprint.
          return
        end

        searcher.search_for_gpg_key
        keys = searcher.results.gpg_keys
        if keys && keys.length == 1
          return redirect_to gh_stafftools_user_gpg_key_path(keys.first)
        end

        searcher.search_for_users
        users = searcher.results.users
        deleted_users = searcher.results.deleted_users

        searcher.search_for_businesses
        businesses = searcher.results.businesses
        deleted_businesses = searcher.results.deleted_businesses

        searcher.search_for_customers
        customers = searcher.results.customers

        searcher.search_for_hook
        hook = searcher.results.hook

        if users.empty? && deleted_users.empty?
          searcher.search_for_renamed_users
          renamed_user = searcher.results.renamed_user
        end

        searcher.search_for_repositories
                .search_for_gists
                .search_for_oauth_application
                .search_for_integrations
                .search_for_teams
                .search_by_global_relay_id

        repositories = searcher.results.repositories
        gists = searcher.results.gists
        oauth_apps = searcher.results.oauth_apps
        integrations = searcher.results.integrations
        integration_installations = searcher.results.integration_installations
        teams = searcher.results.teams

        # There are some situations where we can take a user straight to the only
        # possible result, lets do it if we can.
        forwardable_results_size = \
          users.length +
          repositories.length +
          gists.length +
          businesses.length +
          teams.length
        forwardable_result = \
          deleted_users.empty? &&
          deleted_businesses.empty? &&
          oauth_apps.empty? &&
          renamed_user.nil? &&
          integrations.empty? &&
          integration_installations.empty? &&
          hook.nil? &&
          customers.empty? &&
          forwardable_results_size == 1

        if forwardable_result
          if users.length == 1
            # The regular user page 404s for Bots, so redirect Bots to their integration instead.
            if users.first.bot?
              return redirect_to stafftools_user_app_path(users.first.integration.owner, users.first.integration)
            else
              return redirect_to stafftools_user_path(users.first.login)
            end
          end
          return redirect_to gh_stafftools_repository_path(repositories.first) if repositories.length == 1 && !repositories.first.owner.nil?
          return redirect_to stafftools_user_gist_path(gists.first.user_param, gists.first) if gists.length == 1
          return redirect_to stafftools_enterprise_path(businesses.first) if businesses.length == 1
          return redirect_to gh_stafftools_team_path(teams.first) if teams.length == 1
        end

        render "stafftools/search/search", locals: { results: searcher.results, query: searcher.query } unless performed?
      end

      format.json do
        render json: { error: "Not Found" }, status: :not_found
      end
    end
  end

  def search_results_async # rubocop:todo GitHub/UseRestfulActions
    response_data = {}
    searcher = ::Stafftools::Searcher.new(params[:query], current_user)
    if app = searcher.search_for_oauth_application_by_key.results.oauth_application
      response_data[:redirectUrl] = stafftools_user_application_path(app.user, app.id)
      render json: response_data
      return
    end

    if app = searcher.search_for_integration_by_key.results.integration
      response_data[:redirectUrl] = stafftools_user_app_path(app.user, app.slug)
      render json: response_data
      return
    end

    if access = searcher.search_for_oauth_access_token.results.oauth_access
      response_data[:redirectUrl] = stafftools_user_oauth_token_path(access.user, access.id)
      render json: response_data
      return
    end

    if key = searcher.search_for_public_key.results.public_key
      if key.repository
        # Found a deploy key.
        response_data[:redirectUrl] = gh_stafftools_repository_path(key.repository)
        render json: response_data
      else
        response_data[:redirectUrl] = stafftools_user_path(key.user)
        render json: response_data
      end

      # Return to stop execution and prevent ElasticSearch errors searching
      # for something that looks like a key fingerprint.
      return
    end

    searcher.search_for_gpg_key
    keys = searcher.results.gpg_keys
    if keys && keys.length == 1
      response_data[:redirectUrl] = gh_stafftools_user_gpg_key_path(keys.first)
      render json: response_data
      return
    end

    searcher.search_for_users
    users = searcher.results.users
    deleted_users = searcher.results.deleted_users

    searcher.search_for_businesses
    businesses = searcher.results.businesses
    deleted_businesses = searcher.results.deleted_businesses

    searcher.search_for_customers
    customers = searcher.results.customers

    searcher.search_for_hook
    hook = searcher.results.hook

    if users.empty? && deleted_users.empty?
      searcher.search_for_renamed_users
      renamed_user = searcher.results.renamed_user
    end

    searcher.search_for_repositories
            .search_for_gists
            .search_for_oauth_application
            .search_for_integrations
            .search_for_teams
            .search_by_global_relay_id

    repositories = searcher.results.repositories
    gists = searcher.results.gists
    oauth_apps = searcher.results.oauth_apps
    integrations = searcher.results.integrations
    integration_installations = searcher.results.integration_installations
    teams = searcher.results.teams

    # There are some situations where we can take a user straight to the only
    # possible result, lets do it if we can.
    forwardable_results_size = \
      users.length +
      repositories.length +
      gists.length +
      businesses.length +
      teams.length
    forwardable_result = \
      deleted_users.empty? &&
      deleted_businesses.empty? &&
      oauth_apps.empty? &&
      renamed_user.nil? &&
      integrations.empty? &&
      integration_installations.empty? &&
      hook.nil? &&
      customers.empty? &&
      forwardable_results_size == 1

    redirect_url = if forwardable_result
      if users.first&.bot?
        stafftools_user_app_path(users.first.integration.owner, users.first.integration)
      elsif users.length == 1
        stafftools_user_path(users.first.login)
      elsif repositories.length == 1 && !repositories.first.owner.nil?
        gh_stafftools_repository_path(repositories.first)
      elsif gists.length == 1
        stafftools_user_gist_path(gists.first.user_param, gists.first)
      elsif businesses.length == 1
        stafftools_enterprise_path(businesses.first)
      elsif teams.length == 1
        gh_stafftools_team_path(teams.first)
      end
    end

    if redirect_url
      response_data[:redirectUrl] = redirect_url
    else
      if performed?
        response_data.merge!({ error: "Not Found", status: :not_found })
      else
        results_fragment = render_to_string(partial: "stafftools/search/search_results", locals: { results: searcher.results }, formats: [:html])
        response_data[:resultsFragment] = results_fragment unless results_fragment.strip.empty?
      end
    end

    render json: response_data
  end

  def audit_log # rubocop:todo GitHub/UseRestfulActions
    if query = audit_log_params[:query]
      instrument("staff.search_audit_log", query: query)
    else
      instrument("staff.view_audit_log")
    end
    @default_query_string = default_query_string

    # Set serviceowner to audit log
    push_service_mapping_context

    @current_user = current_user
    respond_to do |format|
      format.html do
        if @current_user.feature_enabled?(:audit_log_async_stafftools)
          # populating @query_string
          filtered_query_string
          return render "stafftools/search/async_audit_log"
        end

        @page = audit_log_params[:page]
        @page = 1 unless @page.present?
        @after = audit_log_params[:after] || ""
        @before = audit_log_params[:before] || ""

        query_opts = {
          phrase: filtered_query_string,
          current_user: current_user,
          page: @page,
          after: @after,
          before: @before,
        }
        es_query = Audit::Driftwood::Query.new_stafftools_query(query_opts)
        GitHub.dogstats.increment(
          "audit.stafftools_search",
          { tags: ["destination:#{es_query.respond_to?(:driftwood_query) ? 'ADE' : 'Elasticsearch'}"] }
        )
        @results = es_query.execute

        @logs = AuditLogEntry.new_from_array(@results)
        collect_audit_log_stats(@logs)

        render "stafftools/search/audit_log"
      end

      format.json do
        query_opts = {
          phrase: filtered_query_string,
          current_user: current_user,
          per_page: 5000,
        }
        es_query = Audit::Driftwood::Query.new_stafftools_query(query_opts)
        results = es_query.execute

        unless audit_log_params[:raw]
          results = AuditLogEntry.new_from_array(results)
          collect_audit_log_stats(results)
          results = results.map { |log| log.metadata(time_zone: ActiveSupport::TimeZone["UTC"]) }
        end

        send_data results.to_json, type: :json, disposition: "attachment"
      end
    end
  end

  def async_query_start # rubocop:todo GitHub/UseRestfulActions
    @after = audit_log_params[:after] || ""
    @before = audit_log_params[:before] || ""

    begin
      query = current_user.audit_log_async_queries.create(phrase: cleaned_query_string, per_page: PER_PAGE, after: @after, before: @before)
    rescue ::AuditLogAsyncQuery::AsyncQueryrror
      return head 500
    end

    respond_with_audit_log_async_query \
      query: query,
      results_url: stafftools_audit_log_query_results_url(query_id: query.query_id, per_page: PER_PAGE, after: @after, before: @before, query: cleaned_query_string),
      status_url: stafftools_audit_log_query_status_url(operation_id: query.operation_id)
  end

  def async_query_status # rubocop:todo GitHub/UseRestfulActions
    begin
      query = current_user.audit_log_async_queries.find_by_operation_id!(params[:operation_id])
      respond_with_audit_log_async_query_status(query)
    rescue ::AuditLogAsyncQuery::AsyncQueryrror
      head 500
    end
  end

  def async_query_results # rubocop:todo GitHub/UseRestfulActions
    query = current_user.audit_log_async_queries.find_by_query_id!(audit_log_params[:query_id])
    results = {}
    begin
      results = query.results(per_page: PER_PAGE, after: audit_log_params[:after], before: audit_log_params[:before])
    rescue ::AuditLogAsyncQuery::AsyncQueryrror
      return render partial: "stafftools/search/results_not_found"
    end

    hits = results_to_elastic_hits(results)

    @logs = AuditLogEntry.new_from_array(hits)
    collect_audit_log_stats(@logs)

    view = create_view_model(
      Stafftools::Search::AuditLogView,
      logs: @logs,
      query_string: cleaned_query_string,
      current_user: current_user,
      results: results,
    )

    render partial: "stafftools/search/results", locals: { view: view }
  end

  helper_method :results

  def audit_log_advanced_search # rubocop:todo GitHub/UseRestfulActions
    unless GitHub.enterprise?
      redirect_to stafftools_audit_log_path
      return
    end

    render "stafftools/search/audit_log_advanced_search"
  end

  def cname # rubocop:todo GitHub/UseRestfulActions
    query = (params[:query] || "").strip.
    gsub(/^(http(s)*:\/\/)*(?<domain>.[^\/]*)(\/)*/, '\k<domain>')
    if query.blank?
      redirect_to stafftools_path
      return
    end

    page = Page.find_by(cname: query)
    if page && page.repository
      redirect_to stafftools_repository_pages_path(page.repository)
    elsif page
      flash[:error] = "Invalid page record (ID: #{page.id}) found for '#{query}'."
      redirect_to stafftools_path
    else
      flash[:error] = "No pages found for '#{query}'."
      redirect_to stafftools_path
    end
  end

  def user_assets # rubocop:todo GitHub/UseRestfulActions
    url = (params[:query] || "").strip
    result = AssetScanner.check_url(url)

    if result.success?
      if asset = UserAsset.where(guid: result.match.asset_guid).first
        redirect_to stafftools_user_asset_path(asset)
      else
        flash[:error] = "No image attachment found with GUID #{result.match.asset_guid}."
        redirect_to stafftools_path
      end
    else
      flash[:error] = "Invalid image attachment URL."
      redirect_to stafftools_path
    end
  end

  def repository_files # rubocop:todo GitHub/UseRestfulActions
    url = (params[:query] || "").strip
    match = url.match(/(\/user-attachments)?\/files\/(?<id>\d+)\/(?<name>.*)/)

    if match.nil?
      flash[:error] = "Invalid file attachment URL."
      redirect_to stafftools_path
    else
      if repository_file = RepositoryFile.where(id: match[:id]).first
        redirect_to gh_stafftools_repository_repository_file_path(repository_file)
      else
        flash[:error] = "No file attachment found with id #{match[:id]}."
        redirect_to stafftools_path
      end
    end
  end

  def actions_workflow_execution # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.actions_enabled?

    respond_to do |format|
      format.html do
        search_id = (params[:query] || "").strip
        if !search_id.match?(/\A\d+\z/)
          flash[:error] = "Invalid check suite id. Id should be a number."
          return redirect_to stafftools_path
        end

        workflow_runs = Actions::WorkflowRun.where(id: search_id).or(Actions::WorkflowRun.where(check_suite_id: search_id))
        workflow_runs = (workflow_runs + CheckRun.where(id: search_id).filter_map { |check_run| check_run.check_suite&.workflow_run }).uniq
        if workflow_runs.one?
          workflow_run = workflow_runs.first
          redirect_to actions_workflow_execution_stafftools_repository_path(
            workflow_run.repository.owner,
            workflow_run.repository,
            workflow_run.check_suite_id
          )
        else
          render "stafftools/search/actions_workflow_execution", locals: { workflow_runs: workflow_runs, query: search_id } unless performed?
        end
      end
      format.json do
        render json: { error: "Not Found" }, status: :not_found
      end
    end
  end

  def logical_service # rubocop:todo GitHub/UseRestfulActions
    case action_name
    when "audit_log"
      "#{GitHub::ServiceMapping::SERVICE_PREFIX}/audit_log"
    else
      super
    end
  end

  private

  def filtered_query_string
    @query_string = params[:query]
    @query_string.blank? ? default_query_string : @query_string
  end

  def default_query_string
    ts = 2.days.ago.strftime("%Y-%m-%d")

    if GitHub.enterprise?
      "@timestamp:>#{ts}"
    else
      <<~KQL
        // Here is a sample KQL statement for searching for all events created on and after #{ts}

        webevents
        | where _timestamp >= datetime('#{ts}')
      KQL
    end
  end

  def cleaned_query_string
    filtered_query_string.gsub(/(^\/\/.+)/, "")
  end

  def collect_audit_log_stats(results)
    return if results.empty?
    last = results.min { |a, b| a.at_timestamp <=> b.at_timestamp }
    log_date = last.at_timestamp
    today = Time.now

    # Calculate how old the last result in the view is
    months_ago = (today.year * 12 + today.month) - (log_date.year * 12 + log_date.month)
    GitHub.dogstats.histogram("audit_log_results.months_old", months_ago, tags: [])
  end

  def audit_log_params
    params.permit(:after, :before, :format, :page, :query, :raw, :authenticity_token, :per_page, :query_id)
  end
  helper_method :audit_log_params

  def results_to_elastic_hits(results)
    t = []
    return t if results[:results].empty?

    results[:results].each do |result|
      t << JSON.parse(result, symbolize_names: true)
    end

    t.map! do |result|
      ::Audit::Elastic::Hit.new(result).tap do |hit|
        hit.after_initialize
        hit.nest_payload! unless @is_api_query
      end
    end

    t
  end
end
