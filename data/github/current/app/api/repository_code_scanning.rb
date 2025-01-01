# typed: true
# frozen_string_literal: true

require "github/codeql/action"

class Api::RepositoryCodeScanning < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeScanningCategoryHelper

  MAX_PAGE = 4294967295 # We limit the maximum page you can request, to prevent overflow when serializing the page number as protobuf.

  # Handle a status report
  put "/repositories/:repository_id/code-scanning/analysis/status", read_from_replicas: true, operation_id: :internal, skip_rate_limit: true do
    @route_owner = "@github/code-scanning-experiences-eng"
    repo = find_repo!

    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    data = receive_with_schema("code-scanning-analysis", "status")
    pull = find_pull_request_from_ref(repo, data["ref"])

    control_access :write_code_scanning,
                    resource: pull || repo,
                    allow_integrations: true,
                    allow_user_via_granular_actor: true,
                    forbid: true

    deliver_error_if_archived! repo

    data[:repository_id] = repo.id
    # nwo not used in response therefore safe to use here.
    data[:repository_nwo] = repo.nwo # rubocop:disable GitHub/DoNotAllowNameWithOwner

    %w[started_at action_started_at completed_at].each do |timestamp_field|
      begin
        data[timestamp_field] = DateTime.parse(data[timestamp_field]) if data[timestamp_field].present?
      rescue ArgumentError
        deliver_error!(400, message: "#{timestamp_field} is not a valid date")
      end
    end

    if data["event_reports"].present?
      %w[started_at completed_at].each do |timestamp_field|
        begin
          data["event_reports"].each_with_index do |event_report, i|
            event_report[timestamp_field] = DateTime.parse(event_report[timestamp_field]) if event_report[timestamp_field].present?
          rescue ArgumentError
            deliver_error!(400, message: "event_reports[#{i}].#{timestamp_field} is not a valid date")
          end
        end
      end
    end

    with_write do
      store_code_scanning_action_in_progress(repo, data)
    end

    GitHub::CodeQLAction.report_status(repo, data)

    deliver_empty(status: 200)
  end

  patch "/repositories/:repository_id/code-scanning/alerts/:alert_number", operation_id: "code-scanning/update-alert" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :write_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_write_message

    deliver_error_if_archived! repo

    data = receive_with_schema("code-scanning-alert", "set-alert-status")

    resolution = :NO_RESOLUTION

    if data["state"] == "dismissed"
      if CodeScanning::AlertDismissalService.new(repo).enabled? && !repo.feature_enabled?(:code_scanning_protected_alert_dismissal_api)
        deliver_error!(400, message: "Delegated alert dismissal is enabled. The alerts cannot be dismissed in the API")
      end
      if data["dismissed_reason"].nil?
        deliver_error!(400, message: "Setting an alert to \"dismissed\" requires a \"dismissed_reason\"")
      end
      dismissed_sym = GitHub::Turboscan.resolution_reason_sym(data["dismissed_reason"])
      resolution = GitHub::Turboscan.to_resolution(dismissed_sym) if dismissed_sym
    else
      %w[dismissed_reason dismissed_comment].each do |dismissal_only_field|
        if data[dismissal_only_field]&.present?
          deliver_error!(400, message: "Can't set a \"#{dismissal_only_field}\" when setting an alert to \"open\"")
        end
      end
    end

    data["dismissed_comment"] = GitHub::Turboscan.normalize_dismissed_comment(data["dismissed_comment"])

    if CodeScanning::AlertDismissalService.new(repo).enabled? && data["state"] == "dismissed"
      if !data["create_request"]
        deliver_error!(400, message: "Delegated alert dismissal is enabled. The alert cannot be dismissed when the create_request parameter is false.")
      end
      deliver_error!(400, message: "Alert dismissal comment is not valid.") if !GitHub::Turboscan.dismissed_request_comment_valid?(data["dismissed_comment"])
      deliver_error!(400, message: "Dismissed reason is not valid.") if !resolution.is_a?(Integer)

      create_dismissal_request!(repo, resolution, data["dismissed_comment"])

      response = GitHub::Turboscan.alert(
        repository_id: repo.id,
        number: alert_number,
      )
      if response.blank? || response.error.present?
        deliver_code_scanning_unavailable_error!
      end

      result = response.data.result
    else
      deliver_error!(400, message: "Alert dismissal comment is not valid.") if !GitHub::Turboscan.dismissed_comment_valid?(data["dismissed_comment"])

      set_alerts_status_options = {
        repository_id: repo.id,
        numbers: [alert_number],
        resolver_id: current_user.id,
        resolver_login: current_user.display_login,
        resolution: resolution,
        resolution_note: data["dismissed_comment"],
      }

      # turboscan will update the alert status successfully as long as the
      # alert exists and turboscan is running.
      # TODO: turboscan currently doesn't distinguish between if the alert was
      # modified or not. If we make it do so, then the check run job triggering
      # below should be conditional on if the status changed or not.
      response = GitHub::Turboscan.set_alerts_status(set_alerts_status_options, repo)

      if response&.error&.code == :not_found
        deliver_error! 404, message: "Couldn't find alert #{alert_number} to set status", documentation_url: @documentation_url
      elsif response.blank? || response.error.present?
        deliver_code_scanning_unavailable_error!
      end

      repo.refresh_code_scanning_status(alert_numbers: [alert_number], refresh_reason: :api_alert_update)

      result = response.data.results.first
    end

    deliver :code_scanning_alert_hash, result, repo: repo
  end

  get "/repositories/:repository_id/code-scanning/alerts", operation_id: "code-scanning/list-alerts-for-repo" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    # fetch only for the default branch (rather than default + protected) if ref wasn't specified
    deliver_error!(400, message: "Only one `ref` parameter is allowed.") if params[:ref].is_a?(Array)
    ref_names = fully_qualified_ref_param(repo)
    if ref_names.empty?
      ref = repo.default_code_scanning_ref_names_bytes[0]
      deliver_error!(404, message: "no default branch found") if ref.nil?
      ref_names = [ref]
    end

    deliver_code_scanning_unavailable_error! if repo.code_scanning_counts_call_failed?
    deliver_error!(404, message: "no analysis found") unless repo.code_scanning_analysis_exists?

    ensure_non_conflicting_tool_params!
    ensure_non_conflicting_cursor_params!

    if pagination[:page] > MAX_PAGE
      deliver_error!(400, message: "Requested page exceeds maximum allowed range.")
    end

    state = GitHub::Turboscan.to_alert_state_filter(params[:state])
    sort_order = GitHub::Turboscan.api_to_alert_sort_order(params[:sort], params[:direction])
    severity = GitHub::Turboscan.to_severity(params[:severity]) if params[:severity]

    # Build a cursor from the parameters - this returns nil if no cursor parameters are present
    cursor = build_cursor(params[:before], params[:after])

    ts_request_params = {
      repository_id: repo.id,
      ref_names_bytes: ref_names,
      state: state,
      limit: per_page,
      numeric_page: pagination[:page],
      sort_order: sort_order,
      tools: [params[:tool_name]].compact,
      tool_guids: [params[:tool_guid]].compact,
      severities: [severity].compact,
      cursor: cursor
    }

    response = GitHub::Turboscan.alerts(ts_request_params)

    if response&.error&.code == :not_found
      # For now, Turboscan only returns :not_found when it can't find the tool, so a specific error message is fine.
      deliver_error! 404, message: "Could not find tool."
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    elsif response.error.nil?
      data = T.must(response.data)

      # Users are currently parsing the Link headers and extracting the page numbers.
      # Therefore we'll only return cursor headers if the user specified a
      # cursor in the first place.
      # Later we hope to deprecate this and only emit cursor headers.
      setup_cursor_links(response) if cursor
      deliver :code_scanning_alerts_hash, { alerts: data.results, total_count: data.total_count }, repo: repo, last_modified: calc_last_modified(data.results)
    end
  end

  get "/repositories/:repository_id/code-scanning/alerts/:alert_number", operation_id: "code-scanning/get-alert" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    response = GitHub::Turboscan.alert(
      repository_id: repo.id,
      number: alert_number,
    )

    if response&.error&.code == :not_found
      deliver_error! 404, message: "No alert found for alert number #{alert_number}", documentation_url: @documentation_url
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    alert = response.data.result

    deliver :code_scanning_alert_hash, alert, repo: repo, last_modified: calc_last_modified_for_object(alert)
  end

  get "/repositories/:repository_id/code-scanning/alerts/:alert_number/instances", operation_id: "code-scanning/list-alert-instances" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_valid_alert_number!(alert_number)

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    deliver_error!(400, message: "Only one `ref` parameter is allowed.") if params[:ref].is_a?(Array)
    ref_names = fully_qualified_ref_param(repo)

    response = GitHub::Turboscan.instances(
      repository_id: repo.id,
      alert_number: alert_number,
      limit: per_page,
      numeric_page: pagination[:page],
      ref_names_bytes: ref_names,
    )

    if response&.error&.code == :not_found
      deliver_error! 404, message: "No alert found", documentation_url: @documentation_url
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    else
      data = T.must(response.data)
      deliver :code_scanning_alert_instances_hash, { instances: data.instances, total_count: data.total_count }, repo: repo
    end
  end

  # For SARIF output we use the following Accept header
  allow_media("application/sarif+json")

  get "/repositories/:repository_id/code-scanning/analyses/:analysis_id", operation_id: "code-scanning/get-analysis" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_positive_analysis_id!

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    ts_request_params = {
      repository_id: repo.id,
      analysis_id: analysis_id,
    }

    sarif = request.accept.any? { |mime| mime.downcase == Mime[:sarif] }

    response = nil
    if sarif
      ts_request_params[:repo_html_url] = repo.permalink
      ts_request_params[:alerts_api_url] = api_url("/repos/#{repo.name_with_display_owner}/code-scanning/alerts")
      response = GitHub::Turboscan.analysis_sarif(ts_request_params)
    else
      response = GitHub::Turboscan.analysis(ts_request_params)
    end

    if !sarif && response&.data&.analysis&.status == :PENDING
      deliver_error! 404, message: "No analysis found for analysis ID #{analysis_id}", documentation_url: @documentation_url
    end

    if response&.error&.code.in?([:not_found, :invalid_argument])
      if response&.error&.code == :invalid_argument && response&.error&.msg&.include?("analysis has failed")
        deliver_error! 422, message: "Analysis could not be processed for analysis ID #{analysis_id}", documentation_url: @documentation_url
      end

      deliver_error! 404, message: "No analysis found for analysis ID #{analysis_id}", documentation_url: @documentation_url
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    elsif response.error.nil?
      data = T.must(response.data)
      if sarif
        data = T.cast(data, Turboscan::Proto::AnalysisSarifResponse)
        content_type = changeset_active?(:fix_sarif_content_type) ? "application/sarif+json" : "application/json+sarif"
        deliver_raw(data.sarif, content_type: content_type)
      else
        data = T.cast(data, Turboscan::Proto::AnalysisResponse)
        deliver :code_scanning_analysis_hash, data.analysis, repo: repo
      end
    end
  end

  delete "/repositories/:repository_id/code-scanning/analyses/:analysis_id", operation_id: "code-scanning/delete-analysis" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)
    ensure_positive_analysis_id!

    control_access :delete_code_scanning_analysis,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "You are not authorized to delete analyses"

    receive_with_schema("code-scanning-analysis", "delete", skip_validation: true)

    ts_request_params = {
      repository_id: repo.id,
      analysis_id: analysis_id,
      confirm_config_delete: params.has_key?(:confirm_delete)
    }
    response = GitHub::Turboscan.delete_analysis(ts_request_params)

    if response&.error&.code == :not_found
      deliver_error! 404, message: "No analysis found for analysis ID #{analysis_id}", documentation_url: @documentation_url
    elsif response&.error&.code == :invalid_argument && response&.error&.msg
      # propagate some 400 errors from turboscan to the client
      deliver_error! 400, message: response&.error&.msg
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    # Log the analysis deletion for accountability
    audit_log_payload = {
      actor: current_user,
      repo: repo,
    }
    org = repo.organization
    if org.present?
      audit_log_payload[:org] = org
    end
    if GitHub.single_business_environment?
      audit_log_payload[:business] = GitHub.global_business
    elsif org&.business.present?
      audit_log_payload[:business] = org.business
    end
    GitHub.instrument("repo.code_scanning_analysis_deleted", audit_log_payload)

    repo.refresh_code_scanning_status
    deliver :code_scanning_analysis_deleted_hash, response.data, repo: repo
  end

  get "/repositories/:repository_id/code-scanning/analyses", operation_id: "code-scanning/list-recent-analyses" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    control_access :read_code_scanning,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: code_scanning_forbid_read_message

    ref = params[:ref]
    if ref.present? && !ref.is_a?(String)
      deliver_error! 400, message: "Only one `ref` parameter is allowed."
    end

    ref_names = fully_qualified_ref_param(repo)

    ensure_non_conflicting_tool_params!
    sort_order = GitHub::Turboscan.api_to_analyses_sort_order(params[:sort], params[:direction])

    ts_request_params = {
      repository_id: repo.id,
      ref_names_bytes: ref_names,
      tool: params[:tool_name],
      tool_guid: params[:tool_guid],
      sarif_id: params[:sarif_id],
      limit: per_page,
      numeric_page: pagination[:page],
      sort_order: sort_order,
    }
    original_request_params = ts_request_params.dup

    use_list_recent_analyses_cursor_implementation = repo.feature_enabled?(:list_recent_analyses_cursor_implementation) && pagination[:page] > 0

    if use_list_recent_analyses_cursor_implementation
      # We need to set the cursor based on the page number.
      # The cursor is set to the last analysis of the previous page.
      # This is a workaround for the fact that Turboscan doesn't support
      # paginating by cursor and page at the same time.
      cursor_data = CodeScanning::KV.store.get(Api::RepositoryCodeScanning.list_recent_analyses_cursor_key(repo.id)).value { nil }
      if cursor_data.present?
        cursor = JSON.parse(cursor_data)
        # is this cursor from the previous page?
        if cursor["hash"] == ::Turboscan::Proto::AnalysesRequest.new(**ts_request_params, numeric_page: pagination[:page] - 1).hash
          ts_request_params[sort_order == :ANALYSES_CREATED_DESCENDING ? :before_cursor : :after_cursor] = cursor["id"].to_s
          ts_request_params.delete(:numeric_page)
        end
      end
    end

    response = GitHub::Turboscan.analyses(ts_request_params)
    if response&.error&.code == :not_found
      # For now, Turboscan only returns :not_found when it can't find the tool, so a specific error message is fine.
      deliver_error! 404, message: "Could not find tool."
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    elsif response.error.nil?
      deliver_error!(404, message: "no analysis found") unless response.data.complete_analysis_exists
      data = T.must(response.data)


      response_data = {
        analyses: data.analyses.reject { |analysis| analysis.status == :PENDING },
        total_count: data.total_count,
      }

      if use_list_recent_analyses_cursor_implementation
        if response_data[:analyses].last.present?
          ActiveRecord::Base.connected_to(role: :writing) do
            next_cursor = JSON.dump(
              "hash" => ::Turboscan::Proto::AnalysesRequest.new(original_request_params).hash,
              # TODO: this should come from turboscan and be an opaque string
              "id" => response_data[:analyses].last.id,
            )
            CodeScanning::KV.store.set(Api::RepositoryCodeScanning.list_recent_analyses_cursor_key(repo.id), next_cursor, expires: 5.minutes.from_now)
          end
        end
      end

      deliver :code_scanning_analyses_hash, response_data, repo: repo
    end
  end

  get "/repositories/:repository_id/code-scanning/sarifs/:sarif_id", operation_id: "code-scanning/get-sarif" do
    repo = find_repo!
    ensure_read_access_and_code_scanning_enabled!(repo, forbid: repo.public?)

    ts_request_params = {
      repository_id: repo.id,
      sarif_id: params[:sarif_id]
    }
    status_response = GitHub::Turboscan.get_delivery(ts_request_params)
    if status_response.blank? || (status_response.error.present? && status_response.error&.code != :not_found)
      deliver_code_scanning_unavailable_error!
    end
    pull = status_response.error.present? ? nil : find_pull_request_from_ref(repo, status_response.data.ref)

    control_access :read_code_scanning,
      resource: pull || repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      forbid: true,
      forbid_message: "You are not authorized to read the requested SARIF data."

    if status_response.error.present? && status_response.error&.code == :not_found
      deliver_error!(404, message: "Upload not found.")
    end

    processing_status = nil
    processing_errors = nil
    if status_response.data.errors.present?
      errors = T.must(status_response.data.errors)
      # If any errors happened, we report the processing status as failed.
      # This does not necessarily mean all the analyses in the delivery failed to be processed, just that at least one did.
      processing_status = "failed"
      processing_errors = errors.map(&:message)
    elsif T.cast(status_response.data.analysis_count, Integer) > 0
      # This assumes one analysis per-delivery, which is not technically true but good enough in most cases.
      processing_status = "complete"
    else
      processing_status = "pending"
    end

    deliver :code_scanning_status_hash, { processing_status: processing_status, sarif_id: params[:sarif_id], errors: processing_errors }, repo: repo
  end

  sig { params(repo_id: Integer).returns(String) }
  def self.list_recent_analyses_cursor_key(repo_id)
    "get_analyses:1:#{repo_id}"
  end

  private

  def ensure_positive_analysis_id!
    deliver_error!(400, message: "analysis_id must be greater than zero") if analysis_id < 1
  end

  def alert_number
    int_id_param!(key: :alert_number)
  end

  def analysis_id
    int_id_param!(key: :analysis_id)
  end

  def store_code_scanning_action_in_progress(repo, data)
    return if data["action_name"] != "init" && data["status"] != "starting"

    ref = data["ref"]
    commit_oid = data["commit_oid"]
    analysis_key = data["analysis_key"]
    matrix_vars = data["matrix_vars"]
    workflow_run_id = data["workflow_run_id"]

    # if matrix_vars is not present we can set it to an empty json object and compute a valid category
    matrix_vars = "{}" unless matrix_vars.present?

    if ref.present? && commit_oid.present? && analysis_key.present? && workflow_run_id.present?
      category = compute_category(analysis_key, matrix_vars)
      repo.store_code_scanning_action_in_progress(ref, commit_oid, category, workflow_run_id)
    else
      GitHub.dogstats.increment("store_code_scanning_action_in_progress.failed")
    end
  end

  def fully_qualified_ref_param(repo)
    ref = params[:ref]&.b

    if ref && !ref.starts_with?("refs/pull/")
      # Try to fully qualify refs to pass to Turboscan.
      qualified_ref = repo.refs.find(ref)&.qualified_name
      return [qualified_ref.b] if qualified_ref
    end

    if ref && !ref.starts_with?("refs/")
      # Treat these refs as if they are branch refs, but don't check that they exist to include deleted branches.
      return ["refs/heads/#{ref}"]
    end

    pr = params[:pr]&.b
    # If the pr parameter exists and is a valid integer, treat it as a pull request number.
    if ref.nil? && pr.to_i.to_s == pr
      return ["refs/pull/#{pr}/head", "refs/pull/#{pr}/merge"]
    end

    ref.nil? ? [] : [ref]
  end

  # Builds a cursor from before and after
  def build_cursor(before, after)
    unless before.nil?
      return { value: before, descending: true }
    end
    unless after.nil?
      return { value: after, descending: false }
    end
    nil
  end

  def setup_cursor_links(response)
    prev_cursor = response.data&.prev_cursor
    next_cursor = response.data&.next_cursor
    if prev_cursor.present?
      @links.add_current({ before: prev_cursor, after: nil, page: nil }, rel: "prev")
      @links.add_current({ before: nil, after: "", page: nil }, rel: "first")
    end
    if next_cursor.present?
      @links.add_current({ before: nil, after: next_cursor, page: nil }, rel: "next")
      @links.add_current({ before: "", after: nil, page: nil }, rel: "last")
    end
  end

  def create_dismissal_request!(repo, resolution, dismissed_comment)
    begin
      CodeScanning::AlertDismissalService.request_dismissal(
        repository: repo,
        requester: current_user,
        alert_number: alert_number,
        resolution: resolution,
        resolution_note: dismissed_comment,
        pr_review_thread_id: nil,
        campaign_id: nil,
      )
    rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
      deliver_error!(409, message: "An alert dismissal request already exists.")
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      deliver_error!(400, message: "There was an issue creating the request. Please try again.")
    end
  end
end
