# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/ControllersShouldHaveTests
class Orgs::SecurityAndAnalysis::CustomPatternsController < Orgs::Controller
  # rubocop:enable GitHub/ControllersShouldHaveTests

  javascript_bundle :"secret-scanning-custom-patterns"

  before_action :login_required
  before_action :manage_security_products_permission_required
  before_action :require_secret_scanning_custom_patterns_available

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    only: [:get_custom_pattern_dry_run_results_by_cursor]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new_custom_pattern]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:show_custom_pattern]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:get_custom_pattern_form_actions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    only: [:dry_run_repository_suggestions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    only: [:get_alert_metrics, :get_push_protection_metrics]

  depends_on_clusters ApplicationRecord::Copilot,
    optional: true,
    only: [:new_custom_pattern, :get_push_protection_metrics, :get_custom_pattern_dry_run_results_by_cursor,
      :get_alert_metrics, :get_custom_pattern_form_actions]

  # Load UX to add a new custom pattern
  def new_custom_pattern # rubocop:todo GitHub/UseRestfulActions
    return render_404 if service.max_allowed_custom_patterns_created?(:org, current_organization.id)

    render "secret_scanning_settings/org_add_custom_pattern", locals: {
      pattern: nil,
      owner: current_organization,
      security_and_analysis_path: settings_org_security_analysis_path,
      custom_pattern_form_submit_path: settings_org_security_analysis_create_custom_pattern_path,
      test_custom_pattern_path: settings_org_security_analysis_test_custom_secret_scanning_pattern_path,
      get_generated_expressions_path: settings_org_security_analysis_get_generated_expressions_path,
      error_message: nil,
    }
  end

  # Create a new custom pattern
  def create_custom_pattern # rubocop:todo GitHub/UseRestfulActions
    selector = {}
    selector[:org_scope] = {
      owner_id: current_organization.id
    }

    selected_repos = SecretScanningCustomPatternsHelper.parse_dry_run_selected_repos(params[:selected_repo_ids])
    response = service.add_custom_pattern(
      expression: params[:secret_format],
      display_name: params[:display_name],
      post_processing: SecretScanningCustomPatternsHelper.parse_post_processing(params),
      selector: selector,
      owner: current_organization,
      selected_repos: selected_repos,
    )

    error, _ = service.check_for_custom_patterns_twirp_error(response)
    unless error.nil?
      log_service_error("Unable to create custom pattern", __method__.to_s, error, nil)
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return redirect_to :back
    end

    custom_pattern = SecretScanningCustomPatternsHelper.custom_pattern_from_response(response)
    return render_404 unless custom_pattern.present?

    if response&.data&.error.present?
      return render "secret_scanning_settings/org_add_custom_pattern", locals: {
        pattern: custom_pattern,
        owner: current_organization,
        security_and_analysis_path: settings_org_security_analysis_path,
        custom_pattern_form_submit_path: settings_org_security_analysis_create_custom_pattern_path,
        test_custom_pattern_path: settings_org_security_analysis_test_custom_secret_scanning_pattern_path,
        get_generated_expressions_path: settings_org_security_analysis_get_generated_expressions_path,
        error_message: response.data.error.message,
      }
    end

    GitHub.instrument(
      "org_secret_scanning_custom_pattern.create",
      build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))

    return render_404 unless custom_pattern.state == :UNPUBLISHED

    if response&.data&.warning&.type == :UNBOUNDED_WILDCARD
      flash[:show_wildcard_warning] = true
    end

    redirect_to settings_org_security_analysis_show_custom_pattern_path(id: custom_pattern.id)
  end

  # Show a custom pattern and allow updates
  def show_custom_pattern # rubocop:todo GitHub/UseRestfulActions
    error, code = service.check_for_custom_patterns_twirp_error(service_response)
    if code == :not_found
      # user triggered 404 - this is not a failure
      return render_404
    end

    custom_pattern = SecretScanningCustomPatternsHelper::custom_pattern_from_response(service_response)

    if error.present? || custom_pattern.nil?
      log_service_error("Unable to fetch custom pattern from server", __method__.to_s, error, params[:id])
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_404
    end

    if custom_pattern.state == :DELETED
      # This is a legitimate scenario and we are working as expected, so we count it as a success.
      return render_404
    end

    dry_run_info = custom_pattern_dry_run_info(params[:id], custom_pattern.row_version)

    case custom_pattern.state
    when :UNPUBLISHED
      mode = :unpublished
    when :PUBLISHED
      mode = :published
    else
      mode = nil
    end

    form_actions_path = settings_org_security_analysis_get_custom_pattern_form_actions_path(id: custom_pattern.id, mode: mode)

    render "secret_scanning_settings/org_show_custom_pattern", locals: {
      custom_pattern: custom_pattern,
      owner: current_organization,
      mode: mode,
      security_and_analysis_path: settings_org_security_analysis_path,
      custom_pattern_form_submit_path: settings_org_security_analysis_update_custom_pattern_path,
      test_custom_pattern_path: settings_org_security_analysis_test_custom_secret_scanning_pattern_path,
      remove_custom_pattern_path: settings_org_security_analysis_delete_custom_pattern_path,
      dry_run_info: dry_run_info,
      cancel_custom_pattern_dry_run_path: settings_org_security_analysis_cancel_custom_pattern_dry_run_path,
      form_actions_path: form_actions_path,
      get_alert_metrics_path: settings_org_security_analysis_get_custom_pattern_alert_metrics_path,
      get_push_protection_metrics_path: settings_org_security_analysis_get_custom_pattern_push_protection_metrics_path,
      get_generated_expressions_path: settings_org_security_analysis_get_generated_expressions_path
    }
  end

  def update_custom_pattern # rubocop:todo GitHub/UseRestfulActions
    # Fetch custom pattern from server
    error, _ = service.check_for_custom_patterns_twirp_error(service_response)
    unless error.nil?
      log_service_error("Unable to fetch custom pattern from server", __method__.to_s, error, params[:id])
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_404
    end

    custom_pattern = SecretScanningCustomPatternsHelper.custom_pattern_from_response(service_response)
    return render_404 unless custom_pattern.present?

    # Bail if pattern is deleted already
    if custom_pattern.state == :DELETED
      # This is a legitimate scenario and we are working as expected, so we count it as a success.
      return render_404
    end

    # The user can perform one of two available submit actions here:
    # 1. Save and dry run
    # 2. Publish changes
    # `Save and dry run` updates the pattern in the db, which triggers a dry run
    # `Publish changes` will update the pattern in the db, which triggers a backfill scan for the updated pattern.
    if params[:submit_type] == "save_and_dry_run"
      action = "update_pattern"
      selected_repos = SecretScanningCustomPatternsHelper.parse_dry_run_selected_repos(params[:selected_repo_ids])
      response = service.update_custom_pattern(
        id: params[:id].to_i,
        expression: params[:secret_format],
        post_processing: SecretScanningCustomPatternsHelper.parse_post_processing(params),
        row_version: params[:row_version],
        selected_repos: selected_repos,
        owner: current_organization,
        change_type: :DRY_RUN,
        owner_id: current_organization.id,
        owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE,
      )

      error, res_code = service.check_for_custom_patterns_twirp_error(response)
      if !error.nil?
        if !service.is_row_version_mismatch?(error, res_code)
          log_service_error("Unable to update custom pattern", __method__.to_s, error, params[:id])
          SecretScanning::Util::Stats.track_graceful_failure(env)
        end
        flash[:custom_pattern_error_message] = SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE
        return redirect_to :back
      end

      if response&.data&.warning&.type == :UNBOUNDED_WILDCARD
        flash[:show_wildcard_warning] = true
      end

      GitHub.instrument(
        "org_secret_scanning_custom_pattern.update",
        build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))
    else
      action = "publish_pattern"
      # Publish changes to the custom pattern
      response = service.publish_custom_pattern(
        id: params[:id].to_i,
        row_version: params[:row_version],
        owner_id: current_organization.id,
        owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE,
      )

      error, res_code = service.check_for_custom_patterns_twirp_error(response)
      if !error.nil?
        if !service.is_row_version_mismatch?(error, res_code)
          log_service_error("Unable to publish custom pattern", __method__.to_s, error, params[:id])
          SecretScanning::Util::Stats.track_graceful_failure(env)
        end
        flash[:custom_pattern_error_message] = SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE
        return redirect_to :back
      end

      GitHub.instrument(
        "org_secret_scanning_custom_pattern.publish",
        build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))
    end

    redirect_to settings_org_security_analysis_show_custom_pattern_path
  end

  def update_custom_pattern_settings # rubocop:todo GitHub/UseRestfulActions
    # Fetch custom pattern from server
    error, _ = service.check_for_custom_patterns_twirp_error(service_response)
    unless error.nil?
      log_service_error("Unable to fetch custom pattern from server", __method__.to_s, error, params[:id])
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return render_404
    end

    custom_pattern = SecretScanningCustomPatternsHelper.custom_pattern_from_response(service_response)
    return render_404 unless custom_pattern.present?

    # Bail if pattern is deleted already
    if custom_pattern.state == :DELETED
      # This is a legitimate scenario and we are working as expected, so we count it as a success.
      success = true
      return render_404
    end

    response = service.update_custom_pattern_settings(
      id: params[:id].to_i,
      push_protection_enabled: params[:push_protection_enabled] == "true",
      row_version: params[:row_version],
      owner_id: current_organization.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::ORGANIZATION_SCOPE,
    )

    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if !error.nil?
      if !service.is_row_version_mismatch?(error, res_code)
        log_service_error("Unable to update custom pattern settings", __method__.to_s, error, params[:id])
        SecretScanning::Util::Stats.track_graceful_failure(env)
      end
      flash[:custom_pattern_error_message] = SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE
      return redirect_to :back
    end

    event_name = if params[:push_protection_enabled] == "true"
      "org.secret_scanning_custom_pattern_push_protection_enabled"
    elsif params[:push_protection_enabled] == "false"
      "org.secret_scanning_custom_pattern_push_protection_disabled"
    end

    GitHub.instrument(
      event_name,
      build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))

    flash[:notice] = "Settings updated"
    redirect_to :back
  end

  def delete_custom_patterns # rubocop:todo GitHub/UseRestfulActions
    if params[:pattern].nil?
      return redirect_to :back
    end

    to_delete = params[:pattern].map do |ptrn|
      {
        id: ptrn[:id].to_i,
        row_version: ptrn[:rowVersion]
      }
    end

    response = service.delete_custom_patterns(
      patterns_with_row_versions: to_delete,
      owner_id: current_organization.id,
      owner_scope: GitHub::Proto::SecretScanning::Api::V3::OwnerScope::ORGANIZATION_SCOPE,
      deleted_by_user_id: current_user.id.to_i,
      post_delete_action: SecretScanningCustomPatternsHelper.parse_post_delete_action(params[:post_delete_action])
    )

    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if !error.nil?
      if !service.is_row_version_mismatch?(error, res_code)
        log_service_error("Unable to delete custom patterns", __method__.to_s, error, nil)
        SecretScanning::Util::Stats.track_graceful_failure(env)
      end
      flash[:custom_pattern_error_message] = SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE
      return redirect_to :back
    end

    custom_patterns = service.get_custom_patterns_by_id(params[:pattern].map { |ptrn| ptrn[:id].to_i }, [:DELETED])&.data&.custom_patterns
    if custom_patterns.nil?
      log_service_error("failed to fetch deleted patterns after they were deleted", __method__.to_s, error, params[:pattern].join(","))
      SecretScanning::Util::Stats.track_graceful_failure(env)
      return redirect_to settings_org_security_analysis_path
    end
    custom_patterns.each do |custom_pattern|
      GitHub.instrument(
        "repository_secret_scanning_custom_pattern.delete",
        build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))
    end
    redirect_to settings_org_security_analysis_path
  end

  def delete_custom_pattern # rubocop:todo GitHub/UseRestfulActions
    response = service.delete_custom_pattern(
      pattern_id: params[:id].to_i,
      deleted_by_user_id: current_user.id.to_i,
      post_delete_action: SecretScanningCustomPatternsHelper.parse_post_delete_action(params[:post_delete_action]),
      row_version: params[:row_version],
      owner_id: current_organization.id,
      owner_scope: GitHub::Proto::SecretScanning::Types::V1::OwnerScope::ORGANIZATION_SCOPE,
    )

    error, res_code = service.check_for_custom_patterns_twirp_error(response)
    if !error.nil?
      if !service.is_row_version_mismatch?(error, res_code)
        log_service_error("Unable to delete custom pattern", __method__.to_s, error, params[:id])
        SecretScanning::Util::Stats.track_graceful_failure(env)
      end
      flash[:custom_pattern_error_message] = SecretScanning::Services::CustomPatternsService::GENERIC_TSS_CUSTOM_PATTERN_ERROR_MESSAGE
      return redirect_to :back
    end

    selector = { org_selector: { owner_id: current_organization.id } }
    custom_pattern = SecretScanningCustomPatternsHelper.custom_pattern_from_response(service.get_custom_pattern(params[:id].to_i, selector))
    return render_404 unless custom_pattern.present?

    GitHub.instrument(
      "org_secret_scanning_custom_pattern.delete",
      build_instrumentation_payload(actor: current_user, org: current_organization, custom_pattern: custom_pattern))
    redirect_to settings_org_security_analysis_path
  end

  # Validate a custom pattern against test code
  def test_custom_secret_scanning_pattern # rubocop:todo GitHub/UseRestfulActions
    response = service.test_custom_pattern(
      display_name: params[:display_name],
      source_string: params[:test_code],
      expression: params[:secret_format],
      post_processing: SecretScanningCustomPatternsHelper.parse_post_processing(params),
    )
    if params[:test_only]
      render html: response[:pattern_matches].to_s
    else
      respond_to do |format|
        format.json do
          render json: SecretScanningCustomPatternsHelper.to_json_pattern_matches(response[:pattern_matches], response[:error], response[:has_wildcard_warning])
        end
      end
    end
  end

  def get_custom_pattern_form_actions # rubocop:todo GitHub/UseRestfulActions
    custom_pattern = SecretScanningCustomPatternsHelper::custom_pattern_from_response(service_response)
    return render_404 if custom_pattern.nil? || custom_pattern.state == :DELETED
    dry_run_info = custom_pattern_dry_run_info(params[:id], custom_pattern.row_version)

    respond_to do |format|
      format.html do
        render SecretScanning::CustomPatterns::FormComponent.new(
          pattern: custom_pattern,
          owner: current_organization,
          mode: :unpublished,
          settings_path: settings_org_security_analysis_path,
          submit_path: settings_org_security_analysis_update_custom_pattern_path,
          update_custom_pattern_settings_path: settings_org_security_analysis_update_custom_pattern_settings_path,
          test_pattern_path: settings_org_security_analysis_test_custom_secret_scanning_pattern_path,
          remove_pattern_path: settings_org_security_analysis_delete_custom_pattern_path,
          show_publish_alert_message: true,
          dry_run_info: dry_run_info,
          cancel_custom_pattern_dry_run_path: settings_org_security_analysis_cancel_custom_pattern_dry_run_path,
          form_actions_path: settings_org_security_analysis_get_custom_pattern_form_actions_path(id: custom_pattern.id, mode: :unpublished),
          get_alert_metrics_path: settings_org_security_analysis_get_custom_pattern_alert_metrics_path,
          get_push_protection_metrics_path: settings_org_security_analysis_get_custom_pattern_push_protection_metrics_path,
          get_generated_expressions_path: settings_org_security_analysis_get_generated_expressions_path,
          error_message: flash[:custom_pattern_error_message]
        ), layout: false
      end
    end
  end

  # Cancel dry runs associated with the custom pattern
  def cancel_custom_pattern_dry_run # rubocop:todo GitHub/UseRestfulActions
    scan_ids = SecretScanningCustomPatternsHelper.parse_scan_ids(params[:scan_ids], current_organization, :ORGANIZATION_SCOPE)
    success = service.cancel_dry_run_service(id: params[:id].to_i, scan_ids: scan_ids, owner: current_organization, owner_scope: :ORGANIZATION_SCOPE)
    unless success
      flash[:error] = SecretScanningCustomPatternsHelper::DRY_RUN_CANCEL_FAILED_MESSAGE
    end
    redirect_to settings_org_security_analysis_show_custom_pattern_path(id: params[:id])
  end

  def get_custom_pattern_dry_run_results_by_cursor # rubocop:todo GitHub/UseRestfulActions
    cursor = nil
    if params[:next_cursor_button]
      cursor = params[:next_cursor]
    elsif params[:previous_cursor_button]
      cursor = params[:previous_cursor]
    end
    custom_pattern = SecretScanningCustomPatternsHelper::custom_pattern_from_response(service_response)
    return render_404 unless custom_pattern.present?

    dry_run_info = custom_pattern_dry_run_info(params[:id], custom_pattern.row_version, cursor)

    respond_to do |format|
      format.html do
        render SecretScanning::CustomPatterns::DryRun::StatusComponent.new(
          pattern_id: params[:id],
          pattern_owner_id: current_organization.id,
          pattern_scope: :org_scope,
          dry_run_info: dry_run_info,
          user: current_user,
        ), layout: false
      end
    end
  end

  def custom_pattern_dry_run_info(pattern_id, row_version, cursor = nil) # rubocop:todo GitHub/UseRestfulActions
    return @custom_pattern_dry_run_info if defined?(@custom_pattern_dry_run_info)

    options = {
      dry_run_scope: {
        pattern_id: params[:id].to_i,
        owner_id: current_organization.id,
        owner_scope: :ORGANIZATION_SCOPE,
        row_version: row_version,
      },
    }

    metadata_response = GitHub::TokenScanning::Service::Client.new(current_user).dry_run_metadata_for_pattern(options)
    if metadata_response.nil? || metadata_response.error.present? || metadata_response.data.nil?
      return nil
    end

    unless cursor.nil?
      options[:cursor] = Base64.urlsafe_decode64(cursor)
    end

    results_response = GitHub::TokenScanning::Service::Client.new(current_user).dry_run_results_for_pattern(options)
    if results_response.nil? || results_response.error.present? || results_response.data.nil?
      return nil
    end

    dry_run_results = results_response.data
    dry_run_metadata = metadata_response.data

    {
      next_cursor: dry_run_results.next_cursor,
      previous_cursor: dry_run_results.previous_cursor,
      results: dry_run_results.results,
      status: dry_run_metadata.status,
      scan_status_counts: SecretScanningCustomPatternsHelper::dry_runs_v2_scan_status_count(dry_run_metadata.scan_status_counts.to_a),
      total_result_count: dry_run_metadata.total_result_count,
      started_at: dry_run_metadata.started_at,
      finished_at: dry_run_metadata.finished_at,
    }
  end

  # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
  def service_response # rubocop:todo GitHub/UseRestfulActions
    return @service_response if defined?(@service_response)
    selector = { org_selector: { owner_id: current_organization.id } }
    @service_response = service.get_custom_pattern(params[:id].to_i, selector)
  end

  # Renders autocomplete results for org dry run repo selector
  def dry_run_repository_suggestions # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        render SecretScanning::CustomPatterns::DryRun::RepoAutocompleteSuggestionsComponent.new(
          owner: current_organization,
          query: params[:q],
          user: current_user,
          authorized_orgs: [current_organization],
        ), layout: false
      end
    end
  end

  # Re-renders repo row components for save and dry run dialog
  def dry_run_update_selected_repositories # rubocop:todo GitHub/UseRestfulActions
    parsed_selected_repos = SecretScanningCustomPatternsHelper::parse_dry_run_selected_repos(params[:selected_repo_ids])

    respond_to do |format|
      format.html_fragment do
        render SecretScanning::CustomPatterns::DryRun::SelectedRepositoriesComponent.new(
          custom_pattern_owner: current_organization,
          selected_repo_ids: parsed_selected_repos,
        ), layout: false
      end
    end
  end

  def get_alert_metrics # rubocop:todo GitHub/UseRestfulActions
    custom_pattern = SecretScanningCustomPatternsHelper::custom_pattern_from_response(service_response)
    return render_404 unless custom_pattern.present?

    token_type = "cp_#{custom_pattern.id}"
    metrics = SecretScanning::Services::MetricsService.get_token_alert_metrics(token_type, current_organization, current_user)
    if metrics.nil?
      SecretScanning::Util::Stats.track_graceful_failure(env)
    end

    respond_to do |format|
      format.html do
        pattern_filter = "secret-type:#{custom_pattern.slug}"
        render SecretScanning::CustomPatterns::AlertMetricsComponent.new(
          metrics: metrics,
          pattern_published: custom_pattern.state == :PUBLISHED,
          open_alerts_path: security_center_alerts_secret_scanning_path(current_organization, { query: "is:open #{pattern_filter}" }),
          closed_alerts_path: security_center_alerts_secret_scanning_path(current_organization, { query: "is:closed #{pattern_filter}" }),
          false_positive_alerts_path: security_center_alerts_secret_scanning_path(current_organization, { query: "is:closed resolution:false-positive #{pattern_filter}" }),
        ), layout: false
      end
    end
  end

  def get_push_protection_metrics # rubocop:todo GitHub/UseRestfulActions
    custom_pattern = SecretScanningCustomPatternsHelper::custom_pattern_from_response(service_response)
    return render_404 unless custom_pattern.present?

    token_type = "cp_#{custom_pattern.id}"
    metrics = SecretScanning::Services::MetricsService.get_token_push_protection_metrics(token_type, current_organization, current_user)
    if metrics.nil?
      SecretScanning::Util::Stats.track_graceful_failure(env)
    end

    respond_to do |format|
      format.html do
        render SecretScanning::CustomPatterns::PushProtectionMetricsComponent.new(
          metrics: metrics,
          push_protection_enabled: custom_pattern.push_protection_enabled,
          custom_pattern_created_at: custom_pattern.created_at.to_time,
        ), layout: false
      end
    end
  end

  def get_generated_expressions # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless SecretScanning::Features::Org::CustomPatterns.new(current_organization).generate_expressions_with_ai_enabled?
    return nil unless params[:description].present?

    response = service.get_generated_expressions(params[:description], params[:examples])

    respond_to do |format|
      format.json do
        generated_expressions = []

        error_msg = "Something went wrong. Please try again later."
        if response.nil?
          # An unknown error occurred, so we log it and return a generic error message.
          log_service_error("Unable to get generated expressions", __method__.to_s, "nil response", nil)
        elsif response.error.present?
          log_service_error("Unable to get generated expressions", __method__.to_s, response.error.msg, nil)

          if response.error.code == :resource_exhausted
            error_msg = "Rate limit exceeded. Please retry in a short while."
          end
        else
          error_msg = nil
          response.data.generated_expressions.each do |generated_expression|
            generated_expressions << {
              regex: generated_expression.regex,
              explanation: generated_expression.explanation,
            }
          end
        end

        render json: { generated_expressions: generated_expressions, error_msg: error_msg }, status: :ok
      end
    end
  end

  private

  sig { returns(SecretScanning::Services::CustomPatternsService) }
  memoize def service
    SecretScanning::Services::CustomPatternsService.new(current_user)
  end

  def build_instrumentation_payload(actor:, org:, custom_pattern:)
    payload = {
      user: actor,
      org: org,
      custom_pattern: {
        id: custom_pattern.id,
        name: custom_pattern.display_name,
      }
    }

    payload
  end

  sig { returns(SecretScanning::Features::Owner::CustomPatterns) }
  def custom_patterns_enablement # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @custom_patterns_enablement if defined?(@custom_patterns_enablement)
    @custom_patterns_enablement = SecretScanning::Features::Owner::CustomPatterns.new(current_organization)
  end

  sig { void }
  def require_secret_scanning_custom_patterns_available
    render_404 unless custom_patterns_enablement.feature_available?
  end

  sig { params(log_msg: String, method_name: String, error_message: T.nilable(String), pattern_id: T.nilable(String)).void }
  def log_service_error(log_msg, method_name, error_message, pattern_id)
    GitHub.logger.error(
      log_msg,
      "code.namespace": self.class.name,
      "code.function": method_name,
      "controller.name": self.class.name,
      "controller.action": method_name,
      "org.id": current_organization.id,
      "pattern.id": pattern_id || nil,
      "exception.type": SecretScanning::Services::CustomPatternsService::CUSTOM_PATTERNS_SERVICE_ERROR_TYPE,
      "exception.message": error_message
    )
  end
end
