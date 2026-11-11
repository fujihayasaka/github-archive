# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::AgentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared
  include BusinessAiControls::AgentSessionMetadata

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Repositories,
    ApplicationRecord::IssuesPullRequests

  layout "layouts/react_business"

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-agent-plane"
  end


  allow_verified_fetch only: [:index, :add_subagent, :edit_subagent, :sessions, :organization_suggestions, :user_suggestions, :repository_suggestions, :ruleset_create, :ruleset_show]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :dotcom_required
  before_action :ai_controls_read_required, only: [:index, :sessions, :organization_suggestions, :user_suggestions, :repository_suggestions, :ruleset_show]
  before_action :ai_controls_write_required, only: [:add_subagent, :edit_subagent, :ruleset_create]

  sig { void }
  def index
    payload = AgentsRoutePayload.new(
      swe_policy: copilot_business.swe_agent,
      code_review_policy: copilot_business.code_review,
      source_org: custom_agents_source_org,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      can_admin: this_business&.adminable_by?(current_user) || false,
      can_view_audit_logs: can_view_audit_logs?,
      this_business: this_business,
      copilot_business: copilot_business,
    )

    respond_with_react(
      payload: payload,
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
    add_client_feature_flag([:agent_sessions_no_access_label], entity: this_business)

    # Validate and clamp pagination parameters
    page = [params[:page].to_i, 1].max
    per_page = params[:per_page].to_i
    per_page = BusinessAiControls::AgentSessionProvider::DEFAULT_PER_PAGE if per_page <= 0

    # Validate agent_type against allowed values
    valid_agent_types = BusinessAiControls::AgentSessionProvider.session_agent_filters.map { |f| f[:value] }

    filters = parse_query_filters(params[:query].to_s)
    statuses = filters["status"]
    organization_names = filters["org"]
    agent_types = filters["agent"]
    agent_types = agent_types&.select { |t| valid_agent_types.include?(t) }
    repository_names = filters["repo"]
    user_logins = filters["user"]
    user_ids = nil
    if user_logins.present?
      user_ids = this_business.members.where(login: user_logins).pluck(:id)
    end

    valid_timeframe_filters = BusinessAiControls::AgentSessionMetadata::SESSION_TIMEFRAME_FILTERS.values.map { |f| f[:value] }
    timeframe_filter = filters["timeframe"]&.first
    unless valid_timeframe_filters.include?(timeframe_filter)
      timeframe_filter = BusinessAiControls::AgentSessionMetadata::SESSION_TIMEFRAME_FILTERS[:twenty_four_hours][:value]
    end

    repository_ids = repository_ids_from_names(repository_names)

    # Look up organizations by name (array)
    organization_ids = nil
    if organization_names.present?
      orgs = this_business.organizations.where(login: organization_names)
      organization_ids = orgs.pluck(:id)
    end

    agent_filters = BusinessAiControls::AgentSessionProvider.session_agent_filters
    timeframe_filters = BusinessAiControls::AgentSessionMetadata::SESSION_TIMEFRAME_FILTERS.values

    session_data = BusinessAiControls::AgentSessionProvider.fetch_recent_sessions(
      business: this_business,
      page: page,
      per_page: per_page,
      user: current_user,
      agent_types: agent_types,
      organization_ids: organization_ids,
      statuses: statuses,
      timeframe_filter: timeframe_filter,
      repository_ids: repository_ids,
      user_ids: user_ids
    )

    organizations = BusinessAiControls::AgentSessionProvider.fetch_organizations_with_sessions(this_business)

    respond_with_react(
      payload: SessionsRoutePayload.new(
        sessions: session_data["sessions"],
        pagination: session_data["pagination"],
        heading: "Recent sessions",
        status_display_names: STATUS_DISPLAY_NAMES.map { |name, display_name| { name: name, display_name: display_name  } },
        organizations: organizations,
        agent_filters: agent_filters,
        timeframe_filters: timeframe_filters,
      ),
      title: "AI Controls - Agent Session Activity",
      page_data: {
        selected_link: :businesses_ai_controls_agents,
        sidebar: :ai_controls,
      },
    )
  end

  sig { void }
  def organization_suggestions # rubocop:todo GitHub/UseRestfulActions
    query = params[:q].to_s.strip
    limit = params[:limit]&.to_i || 10
    limit = [[limit, 1].max, 50].min # Clamp between 1 and 50

    suggestions = BusinessAiControls::AgentSessionProvider.fetch_organization_suggestions(
      business: this_business,
      query: query,
      limit: limit
    )

    render json: { suggestions: suggestions }
  end

  sig { void }
  def repository_suggestions # rubocop:todo GitHub/UseRestfulActions
    query = params[:q].to_s.strip
    limit = params[:limit]&.to_i || 10
    limit = [[limit, 1].max, 50].min # Clamp between 1 and 50

    suggestions = BusinessAiControls::AgentSessionProvider.fetch_repository_suggestions(
      business: this_business,
      query: query,
      limit: limit
    )

    render json: { suggestions: suggestions }
  end

  sig { void }
  def user_suggestions # rubocop:todo GitHub/UseRestfulActions
    query = params[:q].to_s.strip
    limit = params[:limit]&.to_i || 10
    limit = [[limit, 1].max, 50].min # Clamp between 1 and 50

    suggestions = BusinessAiControls::AgentSessionProvider.fetch_user_suggestions(
      business: this_business,
      query: query,
      limit: limit
    )

    render json: { suggestions: suggestions }
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
        swe_policy: String,
        code_review_policy: String,
        source_org: T.nilable(Organization),
        can_write: T::Boolean,
        can_admin: T::Boolean,
        can_view_audit_logs: T::Boolean,
        this_business: Business,
        copilot_business: T.nilable(Copilot::Business),
      ).void
    end
    def initialize(swe_policy:, code_review_policy:, source_org:, can_write:, can_admin:, can_view_audit_logs:, this_business:, copilot_business: nil)
      @swe_policy = swe_policy
      @code_review_policy = code_review_policy
      @source_org = source_org
      @can_write = can_write
      @can_admin = can_admin
      @can_view_audit_logs = can_view_audit_logs
      @this_business = this_business
      @copilot_business = T.let(copilot_business || Copilot::Business.new(this_business), Copilot::Business)
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

      can_view_third_party_agents = @copilot_business.any_org_on_enterprise_plan? ||
        (@this_business.feature_flag_enabled?(:"3p_business_settings", default: false) &&
         @copilot_business.copilot_enabled_organizations.any? { |org| org.copilot_plan_business? })

      swe_agent = {
        name: "Copilot Coding Agent",
        policy: @swe_policy,
      }

      code_review_agent = {
        name: "Copilot Code Review",
        policy: @code_review_policy,
      }

      agents = [swe_agent, code_review_agent]

      data = {
        source_org: source_org_data,
        can_write: @can_write,
        can_admin: @can_admin,
        can_view_audit_logs: @can_view_audit_logs,
        can_view_third_party_agents: can_view_third_party_agents,
        agents: agents
      }

      if can_view_third_party_agents
        data[:third_party_agents_enabled] = Copilot::Policies::CodingAgent.enabled?(@copilot_business) || @copilot_business.copilot_organizations.any? { |org| Copilot::Policies::CodingAgent.enabled?(org) }

        if data[:third_party_agents_enabled]
          data[:third_party_agents] =
            AgenticApp.partner_agents.map do |agent_app|
              {
                name: agent_app.display_name,
                enabled: AgenticApp.enterprise_opted_in?(agent_app, @this_business),
                doc_url: agent_app.doc_url,
                toggle_url: UrlHelpers.update_third_party_agent_enterprise_ai_controls_enterprise_path(@this_business, agent_app.slug),
                integration: {
                  avatar_url: agent_app.integration&.preferred_avatar_url,
                }
              }
            end
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

    sig do
      params(
        sessions: T::Array[T::Hash[String, T.untyped]],
        pagination: T::Hash[String, T.untyped],
        heading: String,
        status_display_names: T::Array[T::Hash[String, String]],
        organizations: T::Array[T::Hash[String, T.untyped]],
        agent_filters: T::Array[T::Hash[Symbol, T.untyped]],
        timeframe_filters: T::Array[T::Hash[Symbol, T.untyped]],
      ).void
    end
    def initialize(sessions:, pagination:, heading:, status_display_names:, organizations:, agent_filters:, timeframe_filters:)
      @sessions = sessions
      @pagination = pagination
      @heading = heading
      @status_display_names = status_display_names
      @organizations = organizations
      @agent_filters = agent_filters
      @timeframe_filters = timeframe_filters
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        sessions: @sessions,
        pagination: @pagination,
        heading: @heading,
        status_display_names: @status_display_names,
        organizations: @organizations,
        agent_filters: @agent_filters,
        timeframe_filters: @timeframe_filters,
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


  # Resolves an array of repository name strings to their corresponding database IDs.
  # Only NWO (name-with-owner) format strings like "org-name/repo-name" are processed;
  # standalone names without a "/" are ignored since they cannot be unambiguously resolved.
  # Each owner slug is verified to belong to the current business before looking up repos.
  # Returns nil if no valid repository IDs are found, allowing the caller to skip filtering.
  sig { params(repository_names: T.nilable(T::Array[String])).returns(T.nilable(T::Array[Integer])) }
  def repository_ids_from_names(repository_names)
    return nil if repository_names.blank?

    nwo_names = repository_names.select { |name| name.include?("/") }
    return nil if nwo_names.blank?

    repo_ids = T.let([], T::Array[Integer])

    nwo_names.group_by { |nwo| nwo.split("/", 2).first&.downcase }.each do |owner_slug, nwos|
      repo_names_for_owner = nwos.map { |nwo| nwo.split("/", 2).last }
      owner_id = this_business.organizations.find_by(login: owner_slug)&.id
      next unless owner_id

      repo_ids.concat(Repository.where(owner_id: owner_id, name: repo_names_for_owner).pluck(:id))
    end

    repo_ids.presence
  end

  sig { params(query: String).returns(T::Hash[String, T::Array[String]]) }
  def parse_query_filters(query)
    filters = T.let({}, T::Hash[String, T::Array[String]])
    return filters if query.blank?

    query.scan(/(\w+):(\S+)/) do |key, value|
      filters[key] = value.split(",")
    end

    filters
  end
end
