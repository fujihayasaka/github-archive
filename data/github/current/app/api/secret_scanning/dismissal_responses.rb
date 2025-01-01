# typed: strict
# frozen_string_literal: true

class Api::SecretScanning::DismissalResponses < Api::App
  delete "/repositories/:repository_id/dismissal-responses/secret-scanning/:dismissal_response_id", operation_id: "secret-scanning/dismiss-dismissal-response" do
    repo = find_repo!

    control_access :review_secret_scanning_alert_dismissal_requests,
      resource: repo,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    response_id = params[:dismissal_response_id]
    exemption_response = ::Exemptions::ExemptionResponse.where(id: response_id, reviewer_id: current_user.id).first
    deliver_error!(404, message: "Dismissal response not found") unless exemption_response

    exemption_request = exemption_response.exemption_request
    deliver_error!(404, message: "Response's dismissal request not found") unless exemption_request
    deliver_error!(404, message: "Response's dismissal request is deleted") if exemption_request.deleted?
    deliver_error!(422, message: "Dismissal request is expired") if exemption_request.expired?
    deliver_error!(422, message: "Dismissal request is completed") if exemption_request.completed?
    deliver_error!(422, message: "Dismissal request is cancelled") if exemption_request.cancelled?

    exemption_response.dismissed!
    deliver_empty(status: 204)
  end
end
