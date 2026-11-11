# typed: true
# frozen_string_literal: true

class CopilotSessions::AgentInfoController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include RepositoryControllerMethods

  before_action :login_required
  allow_verified_fetch only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Permissions

  def show
    return render_404 unless request.xhr?

    agent_id = params[:agent_id]&.to_i
    return render json: { error: "agent_id is required" }, status: :bad_request if agent_id.nil?

    agent = AgenticApp.agent_for_integration_id(agent_id)
    return render json: { error: "Agent not found" }, status: :not_found unless agent

    render json: {
      agent_info: {
        id: agent.integration.id,
        slug: agent.slug,
        display_name: agent.display_name,
        avatar_url: helpers.avatar_url_for(agent.integration),
        doc_url: agent.doc_url,
      }
    }
  end

  def index
    return render_404 unless current_repository
    agents = AgenticApp.enabled_for_repository(current_repository, current_user)
    render json: {
      agents: agents.map do |agent|
        {
          id: agent.integration.id,
          name: agent.display_name,
          slug: agent.slug,
          display_name: agent.display_name,
          avatar_url: helpers.avatar_url_for(agent.integration),
          doc_url: agent.doc_url,
        }
      end
    }
  end

  private

  def target_for_conditional_access
    current_user
  end
end
