# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::CustomAgentsSourceOrganizationController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Configurations,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Repositories,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Copilot

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::AiControls::CustomAgentsSourceOrganizationController#update",
    "Businesses::AiControls::CustomAgentsSourceOrganizationController#destroy"
  ].freeze

  before_action :ai_controls_enabled?
  before_action :ai_controls_read_required, only: [:show]
  before_action :ai_controls_write_required, only: [:update, :destroy]

  allow_verified_fetch only: [:update, :destroy]

  sig { void }
  def show
    source_repo_id = this_business.subagent_definitions_source_repository_id
    repo = source_repo_id.present? ? Repositories::Public.find_active(source_repo_id) : nil
    org = repo&.owner

    respond_to do |format|
      format.json do
        if org.present?
          render json: {
            id: org.id,
            display_login: org.display_login,
            avatar_url: org.primary_avatar_url
          }
        else
          render json: {}
        end
      end
    end
  end

  sig { void }
  def update
    org = this_business.organizations.find_by(id: params[:org_id])
    repo = org&.repositories&.find_by(name: Configurable::SubagentDefinitionsSourceRepository::SOURCE_REPO_NAME)

    if repo.present?
      this_business.set_subagent_definitions_source_repository_id(actor: current_user, repo_id: repo.id)
      render json: {
        success: true,
        reason: "updated",
      }
    else
      render json: {
        success: false,
        reason: "missing_required_repository",
      }
    end
  end

  sig { void }
  def destroy
    if this_business.subagent_definitions_source_repository_id.present?
      this_business.unset_subagent_definitions_source_repository_id(actor: current_user)
    end

    head :no_content
  end

  private

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end
end
