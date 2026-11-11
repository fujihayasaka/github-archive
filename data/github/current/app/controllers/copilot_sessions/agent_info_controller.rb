# typed: true
# frozen_string_literal: true

class CopilotSessions::AgentInfoController < ApplicationController
  include ApplicationController::VerifiedFetchDependency
  include AgentAuthorizationStatus
  include RepositoryControllerMethods
  include AgentInfoSerialization

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = T.let([
    "CopilotSessions::AgentInfoController#authorize",
  ].freeze, T::Array[String])

  before_action :login_required
  allow_verified_fetch only: [:show, :authorize]

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

    return render json: { error: "agent_id is required" }, status: :bad_request if params[:agent_id].blank?

    agent_id = Integer(params[:agent_id], exception: false)
    return render json: { error: "agent_id is invalid" }, status: :bad_request if agent_id.nil?

    agent = AgenticApp.agent_for_integration_id(agent_id)
    return render json: { error: "Agent not found" }, status: :not_found unless agent

    render json: { agent_info: serialize_agent_info(agent) }
  end

  def index
    return render_404 unless current_repository
    agents = listed_agents
    authorization_status_field_enabled = authorization_status_field_enabled?

    integration_ids_needing_authorization = Set.new
    if authorization_status_field_enabled
      integration_ids_needing_authorization = integration_ids_needing_authorization(agents.filter_map { |agent| agent.integration&.id })
    end

    render json: {
      agents: agents.map do |agent|
        info = serialize_agent_info(agent)

        if authorization_status_field_enabled
          info[:needs_authorization] = integration_ids_needing_authorization.include?(agent.integration&.id)
        end

        info
      end
    }
  end

  def authorize # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless current_repository && agent_authorization_enabled?

    agent = listed_agent
    return render json: { error: "Agent not found" }, status: :not_found unless agent
    return render json: { error: "Agent does not require authorization" }, status: :unprocessable_entity unless agent_requires_authorization?(agent)

    render json: { authorize_url: oauth_request_url(client_id: agent.integration.key) }
  end

  private

  def target_for_conditional_access
    current_user
  end

  sig { returns(T::Boolean) }
  def agent_filtering_enabled?
    FeatureFlag.vexi.enabled?(:copilot_mission_control_agent_filtering, current_user, default: false)
  end

  sig { returns(T::Boolean) }
  def agent_authorization_enabled?
    FeatureFlag.vexi.enabled?(:copilot_swe_agent_authorization_status, current_user, default: false)
  end

  sig { returns(T::Array[T.untyped]) }
  def listed_agents
    agents = AgenticApp.enabled_for_repository(current_repository, current_user)
    agents = agents.select(&:assignable?) unless agent_filtering_enabled?
    agents
  end

  sig { returns(T.untyped) }
  def listed_agent
    return nil if params[:agent_id].blank?

    agent_id = Integer(params[:agent_id], exception: false)
    return nil if agent_id.nil?

    listed_agents.find { |agent| agent.integration.id == agent_id }
  end

  sig { params(agent: T.untyped).returns(T::Boolean) }
  def agent_requires_authorization?(agent)
    agent.integration&.can_request_oauth_on_install? || false
  end
end
