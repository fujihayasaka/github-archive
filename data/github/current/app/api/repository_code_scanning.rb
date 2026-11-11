# typed: true
# frozen_string_literal: true

require "github/codeql/action"

class Api::RepositoryCodeScanning < Api::App
  include Api::App::CodeScanningHelpers
  include Api::App::CodeScanningCategoryHelper
  include Api::App::CodeqlActionHelpers

  MAX_PAGE = 4294967295 # We limit the maximum page you can request, to prevent overflow when serializing the page number as protobuf.

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

    valid_assignees = nil
    if data.has_key?("assignees")
      valid_assignees = prepare_alert_assignees!(repo, alert_number, data["assignees"])
    end

    result = nil
    if data.has_key?("state")
      result = deliver_dismiss_or_open_alert!(
        data["state"],
        repo,
        data["dismissed_reason"],
        data["dismissed_comment"],
        data["create_request"]
      )
    end

    unless valid_assignees.nil?
      update_alert_assignees!(repo, alert_number, valid_assignees)

      if result.nil?
        response = GitHub::Turboscan.alert(
          repository_id: repo.id,
          number: alert_number,
        )

        if response&.error&.code == :not_found
          deliver_error! 404, message: "No alert found for alert number #{alert_number}", documentation_url: @documentation_url
        elsif response.blank? || response.error.present?
          deliver_code_scanning_unavailable_error!
        end

        result = T.must(response.data).result
      else
        # result will not contain the updated assignees, so we need to set them here
        result.assigned_user_ids = Google::Protobuf::RepeatedField.new(:uint64, valid_assignees.map(&:id))
      end
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

    assignees = params[:assignees]
    if assignees.present?
      ts_request_params[:assigned_users] = parse_assignees(assignees)
    end

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

    include_related_locations = FeatureFlag.vexi.enabled?(
      :code_scanning_alert_show_related_locations,
      repo,
      repo.owner,
      default: false
    )

    response = GitHub::Turboscan.alert(
      repository_id: repo.id,
      number: alert_number,
      include_related_locations:,
    )

    if response&.error&.code == :not_found
      deliver_error! 404, message: "No alert found for alert number #{alert_number}", documentation_url: @documentation_url
    elsif response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end

    alert = response.data.result

    deliver :code_scanning_alert_hash,
      alert,
      repo: repo,
      last_modified: calc_last_modified_for_object(alert),
      include_related_locations:,
      related_locations: response.data.related_locations.to_a
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

  def dismiss_alert!(repo, dismissed_reason, dismissed_comment, create_request)
    deliver_error!(400, message: "Setting an alert to \"dismissed\" requires a \"dismissed_reason\"") if dismissed_reason.nil?

    dismissed_sym = GitHub::Turboscan.resolution_reason_sym(dismissed_reason)
    resolution = GitHub::Turboscan.to_resolution(dismissed_sym) if dismissed_sym

    deliver_error!(400, message: "Dismissed reason is not valid.") if !resolution.is_a?(Integer)

    if CodeScanning::AlertDismissalService.is_dismissed?(repository: repo, alert_number: alert_number)
      deliver_error!(400, message: "Alert is already dismissed.")
    end

    deliver_error!(400, message: "Alert dismissal comment is not valid.") if !GitHub::Turboscan.dismissed_comment_valid?(dismissed_comment)
    dismissed_comment = GitHub::Turboscan.normalize_dismissed_comment(dismissed_comment)

    if CodeScanning::AlertDismissalService.new(repo).delegated_dismissal_enabled?
      deliver_error!(400, message: "Delegated alert dismissal is enabled. The alert cannot be dismissed when the create_request parameter is false.") unless create_request
      deliver_error!(400, message: "Alert dismissal comment is not valid.") unless dismissed_comment.present?

      response = create_dismissal_request!(repo, resolution, dismissed_comment)

      response[:alert]
    else
      CodeScanning::AlertDismissalService.close_alerts(
        repository: repo,
        alert_numbers: [alert_number],
        resolution: resolution,
        resolver: current_user,
        resolution_note: dismissed_comment,
      ).first
    end
  end

  def deliver_open_alert!(repo, dismissed_reason, dismissed_comment)
    if dismissed_reason&.present?
      deliver_error!(400, message: "Can't set a \"dismissed_reason\" when setting an alert to \"open\"")
    end

    if dismissed_comment&.present?
      deliver_error!(400, message: "Can't set a \"dismissed_comment\" when setting an alert to \"open\"")
    end

    if CodeScanning::AlertDismissalService.has_pending_request?(repository: repo, alert_number: alert_number)
      deliver_error!(400, message: "The alert cannot be opened when there is a pending dismissal request.")
    end

    if CodeScanning::AlertDismissalService.is_open?(repository: repo, alert_number: alert_number)
      deliver_error!(400, message: "Alert is already open.")
    end

    CodeScanning::AlertDismissalService.open_alert(
      repository: repo,
      alert_number: alert_number,
      resolver: current_user,
      refresh_reason: :api_alert_update,
    )
  end

  def deliver_dismiss_or_open_alert!(state, repo, dismissed_reason, dismissed_comment, create_request)
    begin
      if state == "dismissed"
        dismiss_alert!(repo, dismissed_reason, dismissed_comment, create_request)
      else
        deliver_open_alert!(repo, dismissed_reason, dismissed_comment)
      end
    rescue CodeScanning::AlertDismissalService::PendingRequestExistsError
      deliver_error!(409, message: "An alert dismissal request already exists.")
    rescue CodeScanning::AlertDismissalService::AlertDismissalError
      deliver_error!(400, message: "There was an issue creating the request. Please try again.")
    end
  end

  def prepare_alert_assignees!(repo, alert_number, assignees)
    # Fetch assignees that are strings
    user_assignees = User.with_logins(assignees)

    # Check permissions for each user
    permission_results = Promise.all(user_assignees.map do |user|
      repo.async_code_scanning_allowed?(:write_code_scanning, user).then do |allowed|
        { user: user, allowed: allowed }
      end
    end).sync

    # Filter valid assignees and collect invalid ones
    valid_assignees = []
    invalid_assignees = []
    permission_results.each do |result|
      if result[:allowed]
        valid_assignees << result[:user]
      else
        invalid_assignees << result[:user]
      end
    end

    # Deliver error for all invalid users at once
    if invalid_assignees.any?
      user_list = invalid_assignees.map(&:display_login).join(", ")
      deliver_error!(422, message: "#{user_list} cannot be assigned to this code scanning alert")
    end

    valid_assignees
  end

  def update_alert_assignees!(repo, alert_number, valid_assignees)
    user_ids = valid_assignees.map(&:id)

    request = ::Turboscan::Proto::SetAssigneesForAlertsRequest.new(
      repository_id: repo.id,
      alert_numbers: [alert_number],
      user_ids:,
      operation_type: ::Turboscan::Proto::SetAssigneesForAlertsOperationType::SET_ASSIGNEES_FOR_ALERTS_OPERATION_TYPE_REPLACE,
      actor_id: current_user.id,
      actor: current_user.display_login,
      org_id: repo.owner_id,
      org: repo.owner.display_login,
      business_id: repo.owner.business&.id,
      business: repo.owner.business&.slug,
      repository_nwo: repo.name_with_display_owner,
    )

    response = GitHub::Turboscan.set_assignees_for_alerts(request.to_h)

    if response.blank? || response.error.present?
      deliver_code_scanning_unavailable_error!
    end
  end
end
