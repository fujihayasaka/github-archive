# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokCustomKeysController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :copilot_required
  before_action :parse_json_params, only: [:update, :destroy]
  before_action :require_json_request, only: :update

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:update, :destroy]

  def destroy
    custom_key.actor = current_user
    custom_key.destroy!
    head :ok
  end

  def update
    error = CopilotByok::UpdateCustomKey.call(
      custom_key: custom_key,
      actor: current_user,
      name: params[:name],
      deployment_url: params[:deployment_url],
      models: params[:models],
      api_key: params[:api_key]
    )
    if error
      render json: { message: error.message }, status: :unprocessable_entity
    else
      head :ok
    end
  end

  private

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end

  sig { returns(CopilotByok::CustomKey) }
  memoize def custom_key
    org.copilot_custom_keys.find(params.expect(:id))
  end

  def require_json_request
    render json: { message: "Only JSON format is supported" }, status: :not_acceptable unless request.format.json?
  end
end
