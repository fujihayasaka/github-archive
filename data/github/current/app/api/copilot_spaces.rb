# typed: true
# frozen_string_literal: true

class Api::CopilotSpaces < Api::App
  include ReceiveSchemaWithOpenApi

  # GET /organizations/:organization_id/copilot-spaces/:space_number
  get "/organizations/:organization_id/copilot-spaces/:space_number",
      operation_id: "copilot-spaces/get-for-org",
      read_from_replicas: true do

    org = find_org!

    return deliver_error 404, message: "Not found" unless (
      FeatureFlag.vexi.enabled?("copilot_spaces_api", org, default: false) ||
      FeatureFlag.vexi.enabled?("copilot_spaces_api", current_user, default: false)
    )

    control_access :get_organization_copilot_space,
      resource: org,
      challenge: true,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    space = find_org_space!(org, params[:space_number])

    deliver_error! 404 unless space.readable_by?(current_user)

    deliver :space_hash, space, user: current_user
  end

  private

  def find_org_space!(organization, space_number)
    space = CopilotSpace.where(owner: organization).find_by(number: space_number)
    deliver_error!(404) unless space
    space
  end
end
