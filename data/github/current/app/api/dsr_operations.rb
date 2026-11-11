# typed: true
# frozen_string_literal: true

class Api::DsrOperations < Api::App
  ADMIN_FORBIDDEN_MESSAGE = "You must be an admin to submit a DSR export request."
  post "/exports/dsr/user/:username", operation_id: "dsr/request-export" do
    GitHub.logger.info("Starting DSR export request.", "gh.user.id.requests" => current_user.display_login)
    # Only enable this endpoint for multi-tenant enterprise
    deliver_error! 404 unless GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:windbeam_integration, default: false)
    GitHub.logger.info("FF is enabled. Starting the control access check.")

    control_access :dsr_export,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid_message: Api::DsrOperations::ADMIN_FORBIDDEN_MESSAGE

    GitHub.logger.info("Finished control access check. User is authorized to make the request. Let's find if the user for export exists.",
      "gh.user.to_export" => params[:username],
      "control_acess" => "granted")

    user = User.find_by_login(params[:username])
    deliver_error! 404 unless user

    GitHub.logger.info("Beginning DSR export for user #{params[:username]}.",
      "user_exists" => "true")

    status_url = "#{GitHub.scheme}://#{GitHub.api_host_name}/exports/dsr/user/#{params[:username]}"
    begin
      Dsr.export_user(user)
      GitHub.logger.info("DSR export request completed.")
      deliver :dsr_export_request_hash, { message: "Initiated data export.", status_url: status_url }
    rescue WindbeamApi::Errors::CommunicationError => e
      if Dsr.latest_export_request(user).present?
        deliver_error! 409, message: "Data export already in progress"
      else
        GitHub.logger.error("DSR export request failed.", "error" => e.message)
        deliver_error! 500, message: "Something went wrong."
      end
    end
  end

  get "/exports/dsr/user/:username", operation_id: "dsr/request-status" do
    GitHub.logger.info("Starting GET request to extract DSR export status.", "gh.user.id.requests" => current_user.display_login)
    deliver_error! 404 unless GitHub.multi_tenant_enterprise? && FeatureFlag.vexi.enabled?(:windbeam_integration, default: false)
    GitHub.logger.info("FF is enabled. Starting the control access check.")

    control_access :dsr_export,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      forbid_message: Api::DsrOperations::ADMIN_FORBIDDEN_MESSAGE

    GitHub.logger.info("Finished control access check. User is authorized to make the request. Let's find if the user requested exists.",
     "gh.user.to_export" => params[:username],
      "control_acess" => "granted")

    user = User.find_by_login(params[:username])
    deliver_error! 404 unless user

    GitHub.logger.info("Beginning the status request for user #{params[:username]}.",
      "user_exists" => "true")

    latest_request = Dsr.latest_export_request(user)
    deliver_error! 404, message: "No export exists" if latest_request.nil?

    GitHub.logger.info("Fetching status.")
    status = {
      READY: "ready",
      IN_PROGRESS: "in progress",
      COMPLETE: "complete",
      FAILED: "failed"
    }.fetch(latest_request.status, "unknown")

    GitHub.logger.info("Status of DSR export is fetched.")

    if status == "complete"
      deliver :dsr_status_request_hash, { status: status, download_urls: Dsr.get_download_urls(user, latest_request.request_id) }
    else
      deliver :dsr_status_request_hash, { status: status }
    end
  end
end
