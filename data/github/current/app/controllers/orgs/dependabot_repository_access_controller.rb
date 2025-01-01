# typed: true
# frozen_string_literal: true

class Orgs::DependabotRepositoryAccessController < Orgs::Controller
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  before_action :manage_security_products_permission_required
  before_action :require_dependabot_repository_access_feature_enabled

  before_action :parse_json_params, only: [:set_allowed_repositories, :set_default_repository_access]
  allow_verified_fetch only: [:set_allowed_repositories, :set_default_repository_access]

  def set_default_repository_access # rubocop:todo GitHub/UseRestfulActions
    access_level = params[:accessLevel]

    case access_level
    when "internal"
      current_organization.set_dependabot_default_repository_access(access_level, actor: current_user)
    when "public"
      current_organization.clear_dependabot_default_repository_access(actor: current_user)
    end

    render json: { notice: "Dependabot repository access updated." }, status: :ok
  end

  def set_allowed_repositories # rubocop:todo GitHub/UseRestfulActions
    allowed_repository_ids = Array(params[:repositoryIds])

    Dependabot::RepositoryAccess
      .for(org: current_organization, actor: current_user)
      .update(repository_ids: allowed_repository_ids)

    render json: { notice: "Dependabot repository access updated." }, status: :ok
  end

  private

  def require_dependabot_repository_access_feature_enabled
    render_404 unless current_organization.dependabot_repository_access_enabled_for?(current_user)
  end
end
