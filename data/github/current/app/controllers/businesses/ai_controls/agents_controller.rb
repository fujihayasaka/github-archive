# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::AgentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories

  layout "layouts/react_business"

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-agent-plane"
  end


  allow_verified_fetch only: [:index, :add_subagent, :edit_subagent, :sessions, :ruleset_create, :ruleset_show]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :dotcom_required
  before_action :ai_controls_read_required, only: [:index, :sessions, :ruleset_show]
  before_action :ai_controls_write_required, only: [:add_subagent, :edit_subagent, :ruleset_create]

  sig { void }
  def index
    respond_with_react(
      payload: AgentsRoutePayload.new(
        swe_enabled: swe_agent_enabled?,
        code_review_enabled: code_review_enabled?,
        swe_policy: copilot_business.swe_agent,
        code_review_policy: copilot_business.code_review,
        source_org: custom_agents_source_org,
        can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
        can_admin: this_business&.adminable_by?(current_user) || false,
        can_view_audit_logs: can_view_audit_logs?,
        this_business: this_business,
        can_view_third_party_agents: this_business.feature_flag_enabled?(:agentshq_policy, default: false)
      ),
      title: "AI Controls",
      app_payload_generator: -> do {
          paths: {
            showRuleset: UrlHelpers.agents_ruleset_show_enterprise_ai_controls_enterprise_path(this_business),
            createRuleset: UrlHelpers.agents_ruleset_create_enterprise_ai_controls_enterprise_path(this_business),
          }
        }
      end,
      page_data: {
        selected_link: :businesses_ai_controls_agents,
        sidebar: :ai_controls,
      },
    )
  end

  sig { void }
  def add_subagent # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      payload: AddSubagentRoutePayload.new(test: "123"),
      title: "AI Controls",
      page_data: {
        selected_link: :businesses_ai_controls_agents,
        sidebar: :ai_controls,
      },
    )
  end

  sig { void }
  def edit_subagent # rubocop:todo GitHub/UseRestfulActions
    respond_with_react(
      payload: EditSubagentRoutePayload.new(test: "123"),
      title: "AI Controls",
      page_data: {
        selected_link: :businesses_ai_controls_agents,
        sidebar: :copilot_control_plane,
      },
    )
  end

  sig { void }
  def sessions # rubocop:todo GitHub/UseRestfulActions
    page = params[:page]&.to_i || 1
    # Load all available sessions for client-side pagination
    per_page = BusinessAiControls::AgentSessionProvider::SESSIONS_QUERY_LIMIT
    session_data = BusinessAiControls::AgentSessionProvider.fetch_recent_sessions(
      business: this_business,
      page: page,
      per_page: per_page,
      user: current_user
    )

    respond_with_react(
      payload: SessionsRoutePayload.new(
        sessions: session_data["sessions"],
        pagination: session_data["pagination"],
        heading: "Recent sessions"
      ),
      title: "AI Controls - Agent Session Activity",
      page_data: {
        selected_link: :businesses_ai_controls_agents,
        sidebar: :ai_controls,
      },
    )
  end

  sig { void }
  def ruleset_create # rubocop:todo GitHub/UseRestfulActions
    begin
      ruleset = SubAgentHandler.create_sub_agent_ruleset(this_business)
      render json: {
        success: true,
        message: "Subagent ruleset created successfully",
        ruleset: {
          id: ruleset.id,
          name: ruleset.name,
          url: ruleset.definition.url(ruleset.id),
          enforcement: ruleset.enforcement,
        },
      }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :conflict
    rescue StandardError => e
      render json: { error: "Failed to create ruleset: #{e.message}" }, status: :internal_server_error
    end
  end

  sig { void }
  def ruleset_show # rubocop:todo GitHub/UseRestfulActions
    begin
      ruleset = SubAgentHandler.find_subagent_ruleset(this_business)
      if ruleset.nil?
        render status: 404, json: {
          success: false,
          message: "Subagent ruleset not found"
        }
        return
      end

      render json: {
        success: true,
        message: "Subagent ruleset retrieved successfully",
        ruleset: {
          id: ruleset.id,
          name: ruleset.name,
          url: ruleset.definition.url(ruleset.id),
          enforcement: ruleset.enforcement,
        }
      }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :conflict
    rescue StandardError => e
      render json: { error: "Failed to show ruleset: #{e.message}" }, status: :internal_server_error
    end
  end

  private

  class AgentsRoutePayload < ReactPayload::Base

    sig { override.returns(String) }
    def route_id
      "agentsRoute"
    end

    sig do
      params(
        swe_enabled: T::Boolean,
        code_review_enabled: T::Boolean,
        swe_policy: String,
        code_review_policy: String,
        source_org: T.nilable(Organization),
        can_write: T::Boolean,
        can_admin: T::Boolean,
        can_view_audit_logs: T::Boolean,
        this_business: Business,
        can_view_third_party_agents: T::Boolean
      ).void
    end
    def initialize(swe_enabled:, code_review_enabled:, swe_policy:, code_review_policy:, source_org:, can_write:, can_admin:, can_view_audit_logs:, this_business:, can_view_third_party_agents:)
      @swe_enabled = swe_enabled
      @code_review_enabled = code_review_enabled
      @swe_policy = swe_policy
      @code_review_policy = code_review_policy
      @source_org = source_org
      @can_write = can_write
      @can_admin = can_admin
      @can_view_audit_logs = can_view_audit_logs
      @this_business = this_business
      @can_view_third_party_agents = can_view_third_party_agents
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      source_org_data = if @source_org
        {
          id: @source_org.id,
          name: @source_org.display_login,
          avatar_url: @source_org.primary_avatar_url
        }
      else
        {
          id: nil,
          name: nil,
          avatar_url: nil
        }
      end

      data = {
        source_org: source_org_data,
        can_write: @can_write,
        can_admin: @can_admin,
        can_view_audit_logs: @can_view_audit_logs,
        agents: [
          {
            name: "Copilot Coding Agent",
            enabled: @swe_enabled,
            policy: @swe_policy,
          },
          {
            name: "Copilot Code Review",
            enabled: @code_review_enabled,
            policy: @code_review_policy,
          }
        ]
      }

      if @can_view_third_party_agents
        data[:third_party_agents] =
          AgenticApp.all_agents.reject(&:global?).map do |agent_app|
            {
              name: agent_app.display_name,
              enabled: AgenticApp.enterprise_opted_in?(agent_app, @this_business),
              doc_url: agent_app.doc_url,
              toggle_url: UrlHelpers.update_third_party_agent_enterprise_ai_controls_enterprise_path(@this_business, agent_app.slug),
            }
          end
      end

      data
    end
  end

  class AddSubagentRoutePayload < ReactPayload::Base

    sig { override.returns(String) }
    def route_id
      "addSubagentRoute"
    end

    sig { params(test: String).void }
    def initialize(test:)
      @test = test
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        test: @test,
      }
    end
  end

  class EditSubagentRoutePayload < ReactPayload::Base

    sig { override.returns(String) }
    def route_id
      "editSubagentRoute"
    end

    sig { params(test: String).void }
    def initialize(test:)
      @test = test
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        test: @test,
      }
    end
  end

  class SessionsRoutePayload < ReactPayload::Base

    sig { override.returns(String) }
    def route_id
      "sessionsRoute"
    end

    sig { params(sessions: T::Array[T::Hash[String, T.untyped]], pagination: T::Hash[String, T.untyped], heading: String).void }
    def initialize(sessions:, pagination:, heading:)
      @sessions = sessions
      @pagination = pagination
      @heading = heading
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        sessions: @sessions,
        pagination: @pagination,
        heading: @heading,
      }
    end
  end

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

  sig { returns(T.nilable(Organization)) }
  def custom_agents_source_org
    repo_id = this_business.subagent_definitions_source_repository_id
    return nil unless repo_id

    repository = Repositories::Public.get_active_or_deleted(repo_id)
    return nil unless repository

    owner = repository.owner
    return nil unless owner.is_a?(Organization)

    owner
  end

  sig { returns(T::Boolean) }
  def can_view_audit_logs?
    return false unless this_business && current_user
    Authz.domain.check_allowed(current_user, :read_enterprise_audit_logs, this_business)
  end
end
