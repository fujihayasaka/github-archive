# typed: true
# frozen_string_literal: true

class Repos::CodeScanningController < AbstractRepositoryController
  include CodeScanningHelper
  include ScanningControllerMethods
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  javascript_bundle :scanning
  javascript_bundle "commit-autofix", only: :show

  before_action :login_required
  before_action :check_code_scanning_read, except: %i(related_location_popover reopen close batch_mark_configuration_outdated mark_configuration_outdated)
  before_action :check_code_scanning_write, only: %i(reopen close batch_mark_configuration_outdated mark_configuration_outdated)
  before_action :writable_repository_required, only: %i(reopen close batch_mark_configuration_outdated mark_configuration_outdated)

  before_action :parse_json_params, only: [:batch_mark_configuration_outdated]

  track_latency_slo "p99-ui-request", 3000, only: [:index, :show]
  track_latency_slo "p50-ui-request", 750, only: [:index, :show]

  allow_verified_fetch only: [:close]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:code_paths]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    only: [:index]
  depends_on_clusters ApplicationRecord::Notify,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    only: [:tool_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:ref_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:related_location_popover]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:rule_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql2,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Iam,
    ApplicationRecord::Memex,
    ApplicationRecord::Notify,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:show_timeline]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Iam,
    only: [:tag_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Iam,
    ApplicationRecord::Notify,
    only: [:batch_mark_configuration_outdated, :mark_configuration_outdated]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [
      :index,
      :ref_list,
      :show,
      :rule_list,
      :tag_list,
      :tool_list,
      :related_location_popover,
      :code_paths,
      :show_timeline,
      :mark_configuration_outdated,
    ],
    optional: true

  PAGE_SIZE = 25

  preload_features [
    :disable_code_scanning
  ]

  def index
    page = params[:page]&.to_i || 1
    tool = tool_from_query

    ensure_sufficient_filters!(parsed_query)

    # See https://github.com/github/github/blob/78fbf2dd1a06c258372365ace08784a73806e2f6/packages/security_products/app/models/repository/code_scanning_dependency.rb#L242
    # for an explanation of why we use language_analysis.language_percentages rather than language_percentages
    # directly.
    language_percentages = current_repository.language_analysis.language_percentages

    # For "invalid" queries, short circuit here and return a blankslate.
    if !parsed_query.is_valid?
      return render "repos/code_scanning/index", locals: {
        language_percentages: language_percentages,
        alert_number_plus_repository_id_to_issues: {},
        view: create_view_model(
          RepositoryCodeScanning::IndexView,
          repository: current_repository,
          query: parsed_query,
          default_query_string: default_query.query_string,
          ref_names: ref_names,
          page: page,
          per_page: PAGE_SIZE,
          # null-object pattern; return enough of a response to show the "no results match" blankslate
          # Faking a response here is a bit of a hack/anti-pattern, but we're accepting that until we refactor toward view components.
          response: ::Twirp::ClientResp.new(
            data: ::Turboscan::Proto::AlertsResponse.new({
              results: [],
              open_count: 0,
              analysis_exists: true,
            }), error: nil),
          selected_tool: tool,
        ),
      }
    end

    paths = parsed_query.paths
    language_paths = parsed_query.language_paths

    req_params = {
      repository_id: current_repository.id,
      excluded_rule_ids: parsed_query.excluded_rule_sarif_identifiers,
      limit: PAGE_SIZE,
      numeric_page: page,
      resolved_only:  parsed_query.closed?,
      sort_order: parsed_query.sort_enum,
      ref_names_bytes: ref_names,
      rule_tags: parsed_query.tags.presence,
      excluded_rule_tags: parsed_query.excluded_tags.presence,
      excluded_tools: parsed_query.excluded_tools,
      excluded_resolutions: parsed_query.excluded_resolution_enums,
      excluded_severities: parsed_query.excluded_severity_enums,
      state: parsed_query.show_all_states? ? ::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_ALL : nil,
      classification: parsed_query.classification_enum,
      search_query: parsed_query.search_query,
      rule_sarif_identifiers: parsed_query.rule_sarif_identifiers,
      tools: parsed_query.tools,
      severities: parsed_query.severity_enums,
      resolutions: parsed_query.resolution_enums,
      file_paths: paths,
      language_file_paths: language_paths,
    }

    response = GitHub::Turboscan.alerts(req_params)

    # Find the issues tracking results
    alert_number_plus_repository_id_to_issues = {}
    if SecurityCenter::FeatureFlagHelper.show_code_scanning_linked_alerts?(current_user, current_repository.owner)
      alert_number_plus_repository_id_to_issues = alerts_issues(results: response&.data&.results, repository: current_repository)
    elsif response&.data&.results.present?
      alert_number_plus_repository_id_to_issues = alert_issues_by_result_number(result_numbers: (response&.data&.results || {}).map(&:number), repository: current_repository)
    end

    view = create_view_model(
      RepositoryCodeScanning::IndexView,
      repository: current_repository,
      query: parsed_query,
      default_query_string: default_query.query_string,
      ref_names: ref_names,
      page: page,
      per_page: PAGE_SIZE,
      response: response,
      selected_tool: tool,
    )
    render "repos/code_scanning/index", locals: {
      view: view,
      alert_number_plus_repository_id_to_issues:,
      language_percentages: language_percentages,
    }
  end

  def show
    if params[:query]
      # We're not using the 'query' param anymore.
      # Since many links to this page still include the param at the moment, we redirect to the page without it,
      # so it is removed from the browser's url bar and does not confuse the user.
      return redirect_to params: request.query_parameters.except(:query)
    end

    alert_number = params[:number].to_i
    # In Turboscan, we can't distinguish between 0 and a missing value, so we get a 500 error if we send 0 to Turboscan.
    return render_404 if alert_number <= 0 || alert_number > Api::App::CodeScanningHelpers::MAX_ALERT_NUMBER
    # If the repository is empty then it cannot have any Code Scanning alerts, but users sometimes try to navigate to the page anyway which causes a nil pointer dereference.
    return render_404 if current_repository.default_branch_ref.nil?

    response = GitHub::Turboscan.alert(
      repository_id: current_repository.id,
      number: alert_number,
      include_related_locations: true,
    )

    result = response&.data&.result

    return render_404 if response&.error&.code == :not_found

    if result.present?
      alert_instance = result.most_recent_instance
      commits = load_commits([alert_instance&.commit_oid].compact).index_by(&:oid)
      blob_map = blobs(alert_instance&.commit_oid, [alert_instance&.location&.file_path])

      # If autofix journey is enabled, use config statuses rather than alert instances
      if current_repository.feature_enabled?(:code_scanning_alert_fix_journey)
        config_statuses_limit = 100
        config_statuses_response = GitHub::Turboscan.alert_configuration_statuses(
          repository_id: current_repository.id,
          alert_number: alert_number,
          limit: config_statuses_limit,
        )
        if config_statuses_response&.data.present? && config_statuses_response&.error.nil?
          config_statuses = config_statuses_response&.data&.statuses || []
          config_statuses_complete = config_statuses.length < config_statuses_limit
          # Filter down to existing refs
          # TODO: rename method
          config_statuses = filter_instances_to_existing_refs(config_statuses)
        end
      else
        instances_limit = 100
        instances_response = GitHub::Turboscan.instances(
          repository_id: current_repository.id,
          alert_number: alert_number,
          limit: instances_limit,
          branches_only: true,
          no_count: true
        )

        if instances_response&.data.present? && instances_response&.error.nil?
          data = T.must(instances_response&.data)
          alert_instances = data.instances
          alert_instances_complete = alert_instances.length < instances_limit

          GitHub.dogstats.increment("code_scanning.showpage.instances_data", tags: ["complete:#{alert_instances_complete}"])

          # Filter down to existing refs
          alert_instances = filter_instances_to_existing_refs(alert_instances)
        end
      end

      if CodeScanning::Autofix.enabled_for_tool?(current_repository, result.tool&.name) && !helpers.result_closed?(result)
        begin
          suggested_fix_alert = CodeScanning::AutofixSuggestion.fetch_all_suggested_fix_alerts(
            repository: current_repository,
            alert_numbers: [alert_number],
            head_commit_oid: alert_instance&.commit_oid
          )[alert_number]
        rescue CodeScanning::AutofixError => e
          Failbot.report!(e)
        end
      end

      # Fetch alert links for sidebar
      alert_links = CodeScanning::AlertLinks.load([CodeScanning::RepoAlertTuple.new(repository_id: current_repository.id, alert_number: alert_number)])
      alert_links_for_result = alert_links.get_links(repo_id: current_repository.id, alert_number: alert_number)
    end

    campaigns_with_counts = []
    if SecurityCampaigns.enabled?(current_repository.owner)
      security_campaigns = SecurityCampaigns::SecurityCampaign.open.where(organization: current_repository.owner).to_a
      campaigns_with_counts = SecurityCampaigns::CampaignWithCounts.for_repo_and_alert_number(
        security_campaigns:,
        repo: current_repository,
        alert_number:,
        user: current_user,
      ) unless security_campaigns.empty?
    end

    pending_dismissal_request = CodeScanning::AlertDismissalService.find_pending_request(repository: current_repository, alert_number: alert_number)

    view = create_view_model(
      RepositoryCodeScanning::ShowView,
      repository: current_repository,
      response: response,
      commit_map: commits,
      alert_instances: alert_instances,
      alert_instances_complete: alert_instances_complete,
      alert_links: alert_links_for_result,
      selected_alert_instance: alert_instance,
      blob_map: blob_map,
      query: parsed_query,
      default_query: default_query,
      selected_tool: result&.tool&.name,
      affected_branches_form_submit_path: repository_code_scanning_batch_mark_configuration_outdated_path,
      read_only_user: is_read_only_user?,
      suggested_fix_alert:,
      campaigns_with_counts: campaigns_with_counts,
      pending_dismissal_request:,
      config_statuses:,
      config_statuses_complete:
    )

    if params[:partial] == "autofix"
      return head(:internal_server_error) if view.turboscan_unavailable?

      return render(partial: "repos/code_scanning/suggested_fix", locals: { view: view })
    end

    render "repos/code_scanning/show", locals: { view: view }
  end

  def ref_list # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render partial: "repos/code_scanning/refs_list",
          locals: {
            view: create_view_model(RepositoryCodeScanning::IndexView,
              repository: current_repository,
              query: parsed_query,
              ref_names: ref_names,
            )
          }
      end

      format.json do
        branch_names = current_repository.heads.refs_with_default_first.map do |branch|
          {
            value: branch.qualified_name,
            description: branch.name_for_display,
          }
        end
        tag_names = current_repository.tags.take(100).map do |tag|
          {
            value: tag.qualified_name,
            description: tag.name_for_display,
          }
        end
        render json: branch_names + tag_names
      end
    end
  end

  def show_timeline # rubocop:todo GitHub/UseRestfulActions
    response = GitHub::Turboscan.timeline_events(
      repository_id: current_repository.id,
      number: params[:number].to_i,
      ref_names_bytes: parsed_query.refs,
    )

    return render_404 if response.nil? || response.error.present?

    proto_timeline_events = T.let(response.data&.events&.to_a || [], T::Array[Turboscan::Proto::TimelineEvent])
    timeline_events = alert_timeline_events(proto_timeline_events)
    timeline_event_commit_oids = timeline_events.map(&:commit_oid).reject(&:blank?)
    commits = commits_by_oid(timeline_event_commit_oids)
    workflow_run_map = workflow_runs(timeline_events)

    if CodeScanning::AlertDismissalService.new(current_repository).enabled?
      timeline_events += CodeScanning::AlertDismissalService.get_timeline_events(
        repository: current_repository,
        alert_number: params[:number].to_i,
        viewer: current_user
      )
      timeline_events.sort_by! { |event| timestamp_to_time(event.timestamp) }
    end

    render CodeScanning::TimelineComponent.new(
      timeline_events: timeline_events,
      commit_map: commits,
      workflow_run_map: workflow_run_map,
      selected_ref: params[:ref],
      repository: current_repository,
    ), layout: false
  end

  def rule_list # rubocop:todo GitHub/UseRestfulActions
    response = GitHub::Turboscan.rules(
      repository_id: current_repository.id,
      tools: parsed_query.tools,
      search_query: params[:q],
    )

    respond_to do |format|
      format.html_fragment do
        rules = format_rules_response_for_dropdown(response)

        render CodeScanning::AlertListSelectPanelComponent.new(
          caption: "Rule",
          header: "Filter by rule",
          select_variant: :multiple,
          options: rules,
          show_clear: parsed_query.contains_qualifier?(name: :rule),
          clear_path: repository_index_path(current_repository, query: parsed_query.remove_qualifier(:rule)),
          list_only: true,
        ), layout: false
      end

      format.json do
        rule_suggestions = response&.data&.rules&.uniq(&:sarif_identifier)&.sort_by(&:sarif_identifier)&.map do |rule|
          { description: rule.short_description, value: rule.sarif_identifier }
        end
        render json: rule_suggestions || []
      end
    end
  end

  sig { params(response: T.nilable(Twirp::ClientResp[T.nilable(::Turboscan::Proto::RulesResponse)])).returns(T::Array[T::Hash[Symbol, T.any(String, T::Boolean)]]) }
  protected def format_rules_response_for_dropdown(response)
    return [] if response.nil? || response.data.nil? || response.error.present?

    response.data&.rules&.map do |rule|
      rule = T.let(rule, Turboscan::Proto::Rule)
      {
        label: rule.short_description,
        sublabel: rule.sarif_identifier,
        url: repository_index_path(current_repository, query: parsed_query.add_or_remove(:rule, rule.sarif_identifier)),
        selected: parsed_query.qualifier_selected?(name: :rule, value: rule.sarif_identifier),
      }
    end
  end

  def tag_list # rubocop:todo GitHub/UseRestfulActions
    response = GitHub::Turboscan.rule_tags(
      repository_id: current_repository.id,
      tools: parsed_query.tools
    )

    respond_to do |format|
      format.html do
        render partial: "repos/code_scanning/tag_list",
          locals: {
            view: create_view_model(RepositoryCodeScanning::IndexView,
              repository: current_repository,
              query: parsed_query,
              response: response,
            )
          }
      end

      format.json do
        tags = response&.data&.rule_tags&.sort&.map { |id| { value: id } }
        render json: tags || []
      end
    end
  end

  def tool_list # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render CodeScanning::AlertListActionMenuComponent.new(
          id: "code-scanning-tool-filter",
          caption: "Tool",
          header: "Filter by tool",
          select_variant: :multiple,
          options: tool_names_and_filter_urls_for_dropdown,
          show_clear: parsed_query.contains_qualifier?(name: :tool),
          clear_path: repository_index_path(current_repository, query: parsed_query.remove_qualifier(:tool)),
          list_only: true,
        ), layout: false
      end

      format.json do
        tools_list = tools.map { |name| { value: Search::ParsedQuery.encode_value(name) } }
        render json: tools_list || []
      end
    end
  end

  protected def tool_names_and_filter_urls_for_dropdown
    tool_counts
    .sort_by { |k, _v| [k.to_s == "CodeQL" ? 0 : 1, k] }
    .map do |tool, count|
      {
        label: tool,
        url: repository_index_path(current_repository, query: parsed_query.add_or_remove(:tool, tool)),
        selected: parsed_query.qualifier_selected?(name: :tool, value: tool),
        count: count,
      }
    end
  end

  def code_paths # rubocop:todo GitHub/UseRestfulActions
    response = GitHub::Turboscan.code_paths(
      repository_id: current_repository.id,
      number: params[:number].to_i,
    )

    return render_404 if response&.error&.code == :not_found

    alert_instance = response&.data&.result&.most_recent_instance
    if alert_instance
      commits = load_commits([alert_instance.commit_oid]).index_by(&:oid)
      code_paths = response&.data&.code_paths || []
      blob_paths = [alert_instance.location&.file_path].concat(
                    code_paths.map(&:steps).flatten.map { |step| step&.location&.file_path },
                   ).compact.uniq
      blob_map = blobs(alert_instance.commit_oid, blob_paths)
    end

    render partial: "repos/code_scanning/code_paths",
      locals: {
        view: create_view_model(RepositoryCodeScanning::CodePathsView,
          repository: current_repository,
          response: response,
          commit_map: commits,
          blob_map: blob_map,
          selected_alert_instance: alert_instance,
        )
      }
  end

  def related_location_popover # rubocop:todo GitHub/UseRestfulActions
    # TODO: how to communicate the location to this controller method?
    # We are currently passing a deconstructed location, but could re-use an
    # existing turboscan endpoint and extract the relevant location, or create
    # a new endpoint that takes a result_number + commit_oid +
    # related_location_index and returns the relevant location

    file_path = params[:file_path]
    commit_oid = params[:commit_oid]

    blob_map = blobs(commit_oid, [file_path])
    blob = blob_map[file_path]

    location = {
      file_path: file_path,
      start_line: params[:start_line].to_i,
      end_line: params[:end_line].to_i,
      start_column: params[:start_column].to_i,
      end_column: params[:end_column].to_i,
    }

    render partial: "repos/code_scanning/related_location_popover_content",
      locals: {
        view: create_view_model(RepositoryCodeScanning::RelatedLocationView,
          repository: current_repository,
          location: location,
          blob: blob,
          commit_oid: commit_oid,
        )
      }
  end

  def close # rubocop:todo GitHub/UseRestfulActions
    resolution = GitHub::Turboscan.to_resolution(params[:reason])
    return head :bad_request if resolution.nil?

    resolution_note = GitHub::Turboscan.normalize_dismissed_comment(params[:resolution_note])
    return head :bad_request if !GitHub::Turboscan.dismissed_comment_valid?(resolution_note)

    alert_numbers = Array(params[:number]).take(PAGE_SIZE).map(&:to_i).uniq
    return head :bad_request if alert_numbers.empty?

    # bulk operations still use ref_names
    # until they are updated, support both ways of passing ref names
    ref_names_bytes = [
      *params.fetch(:ref_names, []).map { |ref_name| ref_name.force_encoding(Encoding::ASCII_8BIT) },
      *params.fetch(:ref_names_b64, []).map { |ref_name_b64| Base64.decode64(ref_name_b64) },
    ].uniq

    set_alerts_status_options = {
      repository_id: current_repository.id,
      resolution: resolution,
      resolver_id: current_user.id,
      resolver_login: current_user.display_login,
      resolution_note: resolution_note,
      numbers: alert_numbers,
      ref_names_bytes: ref_names_bytes,
    }

    response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, current_repository)
    if response.blank? || response.error.present?
      flash[:error] = "There was an issue dismissing the alerts. Please try again."
    else
      refresh_code_scanning_status(alert_numbers)

      # if this request comes from a PR page it should include the id of the alert's review thread
      # so we can resolve it
      pr_review_thread_id = params[:pull_request_review_thread]
      if pr_review_thread_id.present?
        thread = PullRequestReviewThread.find_by(repository_id: current_repository.id, id: pr_review_thread_id)
        if thread&.conversation?
          code_scanning_app = Apps::Privileged.integration(:code_scanning) or fail "code scanning integration not installed!"
          ActiveRecord::Base.connected_to(role: :writing) do
            thread.resolve(resolver: code_scanning_app.bot)
          end
          GitHub.logger.info(
            "Autoresolving conversation for dismissed code scanning alert",
            "code.function": __method__.to_s,
            "controller.name": self.class.name,
            "gh.repo.id": current_repository.id,
            "gh.code_scanning.alert.number": alert_numbers[0],
            "gh.pull_request.review_thread.id": pr_review_thread_id,
          )
        end
      end
    end

    redirect_to :back
  end

  def reopen # rubocop:todo GitHub/UseRestfulActions
    alert_numbers = Array(params[:number]).take(PAGE_SIZE).map(&:to_i).uniq

    if alert_numbers.empty?
      flash[:error] = "There was an issue reopening the alerts. Please try again."
      return redirect_to :back
    end

    # bulk operations still use ref_names
    # until they are updated, support both ways of passing ref names
    ref_names_bytes = [
      *params.fetch(:ref_names, []).map { |ref_name| ref_name.force_encoding(Encoding::ASCII_8BIT) },
      *params.fetch(:ref_names_b64, []).map { |ref_name_b64| Base64.decode64(ref_name_b64) },
    ].uniq

    set_alerts_status_options = {
      repository_id: current_repository.id,
      resolution: :NO_RESOLUTION,
      resolver_id: current_user.id,
      resolver_login: current_user.display_login,
      numbers: alert_numbers,
      ref_names_bytes: ref_names_bytes,
    }

    response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, current_repository)
    if response.blank? || response.error.present?
      flash[:error] = "There was an issue reopening the alerts. Please try again."
    else
      refresh_code_scanning_status(alert_numbers)
    end

    redirect_to :back
  end

  OUTDATED_SUCCESS_FLASH = "Changes to code scanning configurations saved. This might take a while to propagate."
  OUTDATED_ERROR_FLASH = "There was an issue changing the code scanning configuration. Please try again."

  def mark_configuration_outdated # rubocop:todo GitHub/UseRestfulActions
    if !outdated_params_valid?(params)
      return head :bad_request
    end
    GitHub.dogstats.count("code_scanning.showpage.mark_as_outdated_count", 1, tags: ["method:mark_configuration_outdated"])
    GitHub.dogstats.increment("code_scanning.showpage.mark_as_outdated", tags: ["method:mark_configuration_outdated"])
    responses = mark_as_outdated([params])

    if !responses.kind_of?(Array)
      flash[:error] = OUTDATED_ERROR_FLASH
      return redirect_to :back
    end
    current_repository.refresh_code_scanning_status
    flash[:notice] = OUTDATED_SUCCESS_FLASH
    # should always provide a success path but if undefined send the user back to the code scanning page
    path = params["success_path"].presence || repository_code_scanning_results_path
    safe_redirect_to path
  end

  def batch_mark_configuration_outdated # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.json do
        to_be_marked_outdated = params[:mark_as_outdated] || []
        mark_as_outdated_responses = []
        if !all_outdated_params_valid?(to_be_marked_outdated)
          return render json: { analysis_id: nil, error: "bad request" }, status: :bad_request
        end
        GitHub.dogstats.count("code_scanning.showpage.mark_as_outdated_count", to_be_marked_outdated.size, tags: ["method:batch_mark_configuration_outdated"])
        GitHub.dogstats.increment("code_scanning.showpage.mark_as_outdated", tags: ["method:batch_mark_configuration_outdated"])
        if !to_be_marked_outdated.empty?
          responses = mark_as_outdated(to_be_marked_outdated)
          if !responses.kind_of?(Array)
            flash[:error] = OUTDATED_ERROR_FLASH
            return render json: responses, status: :bad_request
          end
          mark_as_outdated_responses = responses
        end

        current_repository.refresh_code_scanning_status
        flash[:notice] = OUTDATED_SUCCESS_FLASH
        return render json: { mark_as_outdated_ids: mark_as_outdated_responses }
      end
    end
  end

  private

  def all_outdated_params_valid?(configurations)
    configurations.each do |conf|
      return false unless outdated_params_valid?(conf)
    end
    true
  end

  def outdated_params_valid?(params)
    if params[:branch_name].present? && !params[:tool_name].nil? && !params[:tool_name].empty? && !params[:category].nil?
      head = current_repository.heads.async_find(params[:branch_name]).sync
      return true unless head.nil?
    end
    false
  end

  def mark_as_outdated(to_be_marked_outdated)
    to_be_marked_outdated.map do |conf|
      branch_name = conf[:branch_name]
      tool = conf[:tool_name]
      category = conf[:category]
      response = GitHub::Turboscan.create_outdated_analysis(
        request.env["HTTP_X_GITHUB_REQUEST_ID"],
        current_repository,
        tool,
        branch_name,
        category
      )

      if response.blank? || response[:error].present?
        return response
      end
      publish_delete_config_instrumentation(tool: tool, branch: branch_name, category: category, actor: current_user)
      response[:id]
    end
  end

  def parsed_query
    query_string = (params[:query].try(:to_str) || "is:open").strip
    @parsed_query ||= Search::Queries::SecurityCenter::CodeScanningRepoQuery.new(query_string)
  end

  def ensure_sufficient_filters!(query)
    default_branch_name = current_repository.default_code_scanning_ref_names.fetch(0, "")
    default_branch_name = default_branch_name.delete_prefix("refs/heads/")

    # If a ref: qualifier exists, don't enforce a branch one, since branch:X
    # is syntactic sugar for ref:refs/heads/X
    return if query.contains_qualifier?(name: :ref) || query.contains_qualifier?(name: :pr) || default_branch_name.blank?

    unless query.contains_qualifier?(name: :branch)
      new_query = query.add_or_remove(:branch, default_branch_name)
      @parsed_query = query.class.new(new_query)
    end
  end

  def default_query
    default_branch_name = current_repository.default_code_scanning_ref_names.fetch(0, "")
    default_branch_name = default_branch_name.delete_prefix("refs/heads/")

    query = "is:open"
    query += " branch:#{default_branch_name}" unless default_branch_name.blank?
    Search::Queries::SecurityCenter::CodeScanningRepoQuery.new(query)
  end

  def blobs(commit_oid, blob_paths)
    blob_map = {}
    if commit_oid
      blob_paths_with_commit = blob_paths.map { |blob_path| [commit_oid, blob_path] }
      # Fetch blob_oids and match them to paths
      blob_oids = current_repository.rpc.read_blob_oids(blob_paths_with_commit, skip_bad: true)
      paths_by_oid = Hash[blob_oids.zip(blob_paths)]

      # Fetch blobs by blob_oid and match them to paths
      raw_blobs = current_repository.rpc.read_blobs(blob_oids.select(&:present?))
      raw_blobs.map do |raw_blob|
        blob_path = paths_by_oid[raw_blob["oid"]]
        blob_map[blob_path] = TreeEntry.new(current_repository, raw_blob.merge("path" => blob_path))
      end
    end
    blob_map
  end

  sig { params(timeline_events: T::Array[CodeScanning::AlertTimelineEvent]).returns(T::Hash[Integer, Actions::WorkflowRun]) }
  def workflow_runs(timeline_events)
    workflow_run_ids = timeline_events.map(&:workflow_run_id).select(&:nonzero?).uniq
    Actions::WorkflowRun.preload(:check_suite).where(id: workflow_run_ids).where(repository: current_repository).index_by(&:id)
  end

  sig { params(proto_events: T::Array[Turboscan::Proto::TimelineEvent]).returns(T::Array[CodeScanning::AlertTimelineEvent]) }
  def alert_timeline_events(proto_events)
    timeline_events = []
    proto_events.map do |proto_event|
      timeline_events << CodeScanning::AlertTimelineEvent.new(
        category: proto_event.category,
        commit_oid: proto_event.commit_oid,
        environment: proto_event.environment,
        file_path: proto_event.file_path,
        id: proto_event.id,
        logical_alert_id: proto_event.logical_alert_id,
        message: proto_event.message,
        ref_name_bytes: proto_event.ref_name_bytes,
        resolution: proto_event.resolution,
        resolution_note: proto_event.resolution_note,
        start_line: proto_event.start_line,
        timestamp: proto_event.timestamp,
        tool_version: proto_event.tool_version,
        type: proto_event.type,
        user_id: proto_event.user_id,
        workflow_run_id: proto_event.workflow_run_id,
      )
    end
    timeline_events
  end

  # ref_names is used to get the refs on the index page
  def ref_names # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @ref_names ||= begin
      query_refs = parsed_query.refs&.map(&:b)
      # Add branches
      query_refs += parsed_query.branches.map { |branch| "refs/heads/#{branch}".b }

      parsed_query.prs.each do |pr|
        m = pr.match(/\A#?(\d+)\Z/)
        if !m
          parsed_query.remove_qualifier!(name: :pr, value: pr)
          next
        end
        pr_number = m[1]

        query_refs << "refs/pull/#{pr_number}/merge"
        query_refs << "refs/pull/#{pr_number}/head"

        pr = PullRequest.with_number_and_repo(pr_number, current_repository)
        query_refs << "refs/heads/#{pr.head_ref}".b if pr

      end
      query_refs.presence || current_repository.default_code_scanning_ref_names_bytes
    end
  end

  def tools # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @tools ||= current_repository.code_scanning_tool_names.sort
  end

  def tool_counts # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @counts if defined?(@counts)
    @counts = Hash.new
    current_repository.code_scanning_counts_by_tool.each do |result|
      @counts[result[:tool_name]] = result[:open_count]
    end
    @counts
  end

  def tool_from_query # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @tool_name_from_query_or_default ||= parsed_query.tool.present? ? parsed_query.tool : nil
  end

  def refresh_code_scanning_status(alert_numbers)
    # no need to refresh anything if no alert was changed
    return unless alert_numbers.present?
    current_repository.refresh_code_scanning_status(alert_numbers: alert_numbers, refresh_reason: :ui_alert_update)
  end

  def filter_instances_to_existing_refs(instances)
    ref_names = instances.map(&:ref_name_bytes)
    refs = current_repository.heads.find_all(ref_names)
    # It would make sense to use lazy enumerators here but that seems to have a bug with the latest Ruby
    # where filter_map does not get the pairs but just the first elements.
    instances.zip(refs).filter_map { |pair| pair[0] unless pair[1].nil? }
  end

  def defer_commit_badges?
    true
  end

  def defer_status_check_rollups?
    true
  end

  def publish_delete_analysis_instrumentation
    # Log the analysis deletion for accountability
    audit_log_payload = {
      actor: current_user,
      repo: current_repository,
    }
    org = current_repository.organization
    if org.present?
      audit_log_payload[:org] = org
    end
    if GitHub.single_business_environment?
      audit_log_payload[:business] = GitHub.global_business
    elsif org&.business.present?
      audit_log_payload[:business] = org.business
    end
    GitHub.instrument("repo.code_scanning_analysis_deleted", audit_log_payload)
  end

  def publish_delete_config_instrumentation(tool:, branch:, category:, actor:)
    payload = {
      tool: tool,
      branch: branch,
      category: category,
      actor: actor,
      repo: current_repository
    }

    org = current_repository.organization
    if org.present?
      payload[:org] = org
    end
    if GitHub.single_business_environment?
      payload[:business] = GitHub.global_business
    elsif org&.business.present?
      payload[:business] = org.business
    end
    GitHub.instrument("repo.code_scanning_configuration_for_branch_deleted", payload)
  end

  def is_read_only_user?
    !current_repository.code_scanning_writable_by?(current_user) &&
      (current_repository.code_scanning_readable_by?(current_user) ||
        current_repository.code_scanning_readable_because_hubber?(current_user))
  end

  def max_pagination_page
    4294967295
  end
end
