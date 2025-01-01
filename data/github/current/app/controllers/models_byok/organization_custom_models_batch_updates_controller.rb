# typed: true
# frozen_string_literal: true

class ModelsByok::OrganizationCustomModelsBatchUpdatesController < Orgs::Controller
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :organization_admin_required
  before_action :github_models_required
  before_action :parse_json_params, only: [:update]

  # Allow making requests to this endpoint from React apps using the `verifiedFetch` function:
  allow_verified_fetch only: [:update]

  def update
    success = ModelsByok::BulkUpdateCustomModels.call(update_params[:models], actor: current_user, org: org)
    head(success ? :ok : :unprocessable_entity)
  end

  private

  def update_params
    params.permit(:organization_id, models: [:id, :copilot_chat_enabled])
  end

  sig { returns(::Organization) }
  memoize def org
    T.cast(this_organization, ::Organization)
  end
end
