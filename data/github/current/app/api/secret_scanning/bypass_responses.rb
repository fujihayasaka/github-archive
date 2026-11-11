# typed: strict
# frozen_string_literal: true

class Api::SecretScanning::BypassResponses < Api::App
  delete "/repositories/:repository_id/bypass-responses/secret-scanning/:bypass_response_id", operation_id: "secret-scanning/dismiss-bypass-response" do
    repo = find_repo!

    control_access :review_secret_scanning_push_protection_requests,
      resource: repo,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    response_id = params[:bypass_response_id]
    exemption_response = ::Exemptions::ExemptionResponse.where(id: response_id).first
    deliver_error!(404, message: "Bypass response not found") unless exemption_response
    deliver_error!(403, message: "Cannot dismiss another reviewer's response") unless exemption_response.reviewer_id == current_user.id

    exemption_request = exemption_response.exemption_request
    deliver_error!(404, message: "Response's bypass request not found") unless exemption_request
    deliver_error!(404, message: "Response's bypass request is deleted") if exemption_request.deleted?
    deliver_error!(422, message: "Bypass request is expired") if exemption_request.expired?
    deliver_error!(422, message: "Bypass request is completed") if exemption_request.completed?
    deliver_error!(422, message: "Bypass request is cancelled") if exemption_request.cancelled?

    exemption_response.dismissed!
    deliver_empty(status: 204)
  end
end
