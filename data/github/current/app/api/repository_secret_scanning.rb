# typed: true
# frozen_string_literal: true

class Api::RepositorySecretScanning < Api::App
  include Api::App::SecretScanningHelpers
  include ReceiveSchemaWithOpenApi
  include SecretScanning::Features::FeatureFlagHelper

  # GA Secret Scanning APIs

  # get a list of secret scanning alerts for a private repository.
  get "/repositories/:repository_id/secret-scanning/alerts", operation_id: "secret-scanning/list-alerts-for-repo" do
    repo = find_repo!

    control_access :read_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    validate_repository_access_for_alerts_apis(repo)

    state = nil
    # Filter by state, if provided in the query
    if params[:state]
      state = params[:state].downcase.to_sym
      if state != :open && state != :resolved
        deliver_error!(400, message: "State needs to be either 'open' or 'resolved'")
      end
    end

    # Filter by resolution, if provided in the query
    resolutions = []
    if params[:resolution]
      params[:resolution].split(",").each do |resolution|
        service_enum = get_service_enum_from_alert_resolution(resolution)
        if service_enum.nil?
          deliver_error!(422, message: "resolution is invalid: it must be one of 'revoked', 'false_positive', 'used_in_tests', 'pattern_deleted', 'pattern_edited' or 'wont_fix'")
        end
        resolutions << service_enum
      end
    end

    # Filter by validity, if provided in the query
    validity_service_params = get_service_enums_from_validity_param(params[:validity])
    unless validity_service_params[:error].nil?
      deliver_error!(422, message: validity_service_params[:error])
    end
    validities = validity_service_params[:validities]

    slug_types = nil
    if params[:secret_type]
      slug_types = params[:secret_type].split(",")
    end

    if params[:secret_types]
      slug_types = params[:secret_types].split(",")
    end

    GitHub.dogstats.distribution("secret_scanning.api.page", pagination[:page], tags: ["scope:repository"])

    results = get_alerts_for_repo(
      repo,
      state,
      slug_types,
      params[:sort],
      params[:direction],
      per_page,
      params[:page],
      params[:before],
      params[:after],
      resolutions,
      validities
    )

    alerts = results[:alerts]

    # If encrypted secrets were retrieved, we may be able to decrypt them here
    alerts.each { |alert| set_raw_secret_from_encrypted_secret(alert) }

    alerts_without_raw_secrets = alerts.select { |alert| alert.raw_secret.blank? }
    alerts_without_raw_secrets.each { |alert| SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(alert) }


    setup_cursor_paging_links(results) if params[:before] || params[:after]

    total_count = results[:total]
    if state == :open
      total_count = results[:unresolved_count]
    elsif state == :resolved
      total_count = results[:resolved_count]
    end

    # current_user can be removed when FF for adding validity is removed.
    # validity is added to the secret scanning alert hash if the FF is enabled for the current user
    deliver(:secret_scanning_alerts_hash, { alerts: alerts, total_count: total_count }, repo: repo)
  end

  # get a specific secret scanning alert by id
  get "/repositories/:repository_id/secret-scanning/alerts/:alert_number", operation_id: "secret-scanning/get-alert" do
    repo = find_repo!

    control_access :read_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    validate_repository_access_for_alerts_apis(repo)

    # Check that the provided :alert_number represents a positive integer
    if alert_number < 1
      deliver_error!(400, message: "alert_number is not valid")
    end

    alert = find_alert_by_number(repo, alert_number)

    if alert.nil?
      deliver_error!(404, message: "No alert found for alert id #{alert_number}", documentation_url: @documentation_url)
    end

    deliver(:secret_scanning_alert_hash, alert, repo: repo, last_modified: calc_last_modified_for_object(alert))
  end

  # update the status of an alert
  patch "/repositories/:repository_id/secret-scanning/alerts/:alert_number", operation_id: "secret-scanning/update-alert" do
    repo = find_repo!

    control_access :write_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    validate_repository_access_for_alerts_apis(repo)

    # Check that the provided :alert_number represents a positive integer
    if alert_number < 1
      deliver_error!(400, message: "alert_number is not valid")
    end

    data = receive_with_openapi

    if data["state"] == "resolved"
      if data["resolution"].nil?
        deliver_error!(422, message: "Setting an alert to \"resolved\" requires a \"resolution\"")
      end

      if data["resolution_comment"]&.present? && data["resolution_comment"].length > 280
        deliver_error!(400, message: "Invalid Argument Error: \"resolution_comment\" must be 280 characters or less")
      end
      resolution = data["resolution"].to_sym
    else
      if data["resolution"]&.present?
        deliver_error!(422, message: "Can't set a \"resolution\" when setting an alert state to \"open\"")
      end
      resolution = :reopened
    end

    if data["state"] == "open" && data["resolution_comment"]&.present?
      deliver_error!(422, message: "cannot set a \"resolution_comment\" when setting an alert state to \"open\"")
    end
    comment = normalize_dismissal_comment(data["resolution_comment"])

    response = resolve_alert_from_service(alert_number, repository: repo, resolution: resolution, actor: current_user, dismissal_comment: comment)

    if response.nil?
      deliver_error!(503, message: "Secret scanning unavailable. Please try again later.")
    end
    if response.error && response.error.code == :not_found
      deliver_error!(404, message: "No alert found for alert id #{alert_number}", documentation_url: @documentation_url)
    end
    if response.error && response.error.code == :invalid_argument
      deliver_error!(400, message: "Invalid Argument Error: " + response.error.msg)
    end
    if response.error && response.error.present?
      deliver_error!(500, message: "Couldn't resolve token " + response.error.msg)
    end

    repo.token_scanning_service_unresolved_cache(current_user).bump

    updated_alert = find_alert_by_number(repo, alert_number)
    log_audit_entry_for_resolution(current_user, repo, alert_number, resolution, updated_alert.token.slug)
    deliver(:secret_scanning_alert_hash, updated_alert, repo: repo)
  end

  # list locations for a given alert
  get "/repositories/:repository_id/secret-scanning/alerts/:alert_number/locations", operation_id: "secret-scanning/list-locations-for-alert" do
    repo = find_repo!

    control_access :read_secret_scanning_alerts,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    validate_repository_access_for_alerts_apis(repo)

    # Check that the provided :alert_number represents a positive integer
    if alert_number < 1
      deliver_error!(400, message: "alert_number is not valid")
    end

    alert = find_alert_with_locations(repo, alert_number, per_page, pagination[:page])

    if alert.nil?
      deliver_error!(404, message: "No alert found for alert id #{alert_number}", documentation_url: @documentation_url)
    end

    deliver(:secret_scanning_alert_locations_hash, { alert: alert, total_count: alert.included_locations_count }, repo: repo)
  end

  # create push protection bypass
  post "/repositories/:repository_id/secret-scanning/push-protection-bypasses", operation_id: "secret-scanning/create-push-protection-bypass" do
    repo = find_repo!

    control_access :bypass_secret_scanning_push_protection,
      resource: repo,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    data = receive_with_openapi

    bypass_placeholder, error_message = SecretScanning::Services::PushProtectionService.get_bypass_placeholder(repo, current_user, data["placeholder_id"])
    if bypass_placeholder.nil? || error_message.present?
      if SecretScanning::Services::PushProtectionService.bypass_placeholder_not_found?(error_message)
        deliver_error!(404, message: "No bypass found for placeholder id #{data["placeholder_id"]}")
      end

      GitHub.logger.error("Failed to get bypass placeholder", "error.message": error_message)
      deliver_error!(500, message: "Failed to bypass push protected secret. Please try again later.")
    end

    if bypass_placeholder.actor_id != current_user.id
      deliver_error!(404)
    end

    response, error_message = SecretScanning::Services::PushProtectionService.promote_bypass(data["reason"], repo, current_user, data["placeholder_id"])
    if response.nil? || error_message.present?
      if SecretScanning::Services::PushProtectionService.bypass_placeholder_not_found?(error_message)
        deliver_error!(404, message: "No bypass found for placeholder id #{data["placeholder_id"]}")
      end

      GitHub.logger.error("Failed to promote push protection bypass", "error.message": error_message)
      deliver_error!(500, message: "Failed to bypass push protected secret. Please try again later.")
    end

    deliver_raw({ reason: response.reason, expire_at: response.expire_at, token_type: response.token_type }, repo: repo)
  end
end
