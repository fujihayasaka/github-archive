# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::ByokCustomKeysController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :require_feature
  before_action :organization_admin_required
  before_action :copilot_required
  before_action :parse_json_params, only: [:update, :destroy]
  before_action :require_json_request, only: :update

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:update, :destroy]

  def destroy
    CopilotByok::DeleteCustomKeyJob.perform_later(custom_key_id: custom_key.id, actor_id: current_user.id)
    head :ok
  end

  def update
    if params[:api_key].present? && !custom_key.update_secret(actor: current_user, api_key: params[:api_key])
      return render json: { message: "Failed to update api key, please try again." }, status: :unprocessable_entity
    end

    error = CopilotByok::UpdateCustomKey.call(
      custom_key: custom_key,
      actor: current_user,
      name: params[:name],
      deployment_url: params[:deployment_url],
      models: params[:models],
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

  def require_feature
    has_feature = user_feature_enabled?(:copilot_byok) ||
      FeatureFlag.vexi.enabled?(:copilot_byok, org, default: false)
    render_404 unless has_feature
  end
end
