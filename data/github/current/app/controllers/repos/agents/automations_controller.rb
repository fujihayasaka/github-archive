# typed: true
# frozen_string_literal: true

require "react_payload"

class Repos::Agents::AutomationsController < AbstractRepositoryController
  include Repos::Agents::Common

  before_action :require_automations_visible

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [].freeze

  depends_on_clusters ApplicationRecord::Authnd,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Permissions,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    only: [:index, :show, :new, :edit]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :show, :new, :edit],
    optional: true

  class IndexPayload < ReactPayload::Base
    def route_id
      "automationsRoute"
    end

    sig { params(base_props: T::Hash[Symbol, T.untyped], automations: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(base_props, automations:)
      @base_props = base_props
      @automations = automations
    end

    def payload
      @base_props.merge(automations: @automations)
    end
  end

  class ShowPayload < ReactPayload::Base
    def route_id
      "automationDetailRoute"
    end

    sig { params(base_props: T::Hash[Symbol, T.untyped], automation: T::Hash[String, T.untyped], tasks: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(base_props, automation:, tasks:)
      @base_props = base_props
      @tasks = tasks
      @automation = automation
    end

    def payload
      @base_props.merge(tasks: @tasks, automation: @automation)
    end
  end

  class NewPayload < ReactPayload::Base
    def route_id
      "newAutomationRoute"
    end

    sig { params(base_props: T::Hash[Symbol, T.untyped], tools: T::Array[T::Hash[String, T.untyped]], triggers: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(base_props, tools:, triggers:)
      @base_props = base_props
      @tools = tools
      @triggers = triggers
    end

    def payload
      @base_props.merge(tools: @tools, triggers: @triggers)
    end
  end

  class EditPayload < ReactPayload::Base
    def route_id
      "editAutomationRoute"
    end

    sig { params(base_props: T::Hash[Symbol, T.untyped], automation: T::Hash[String, T.untyped], tools: T::Array[T::Hash[String, T.untyped]], triggers: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(base_props, automation:, tools:, triggers:)
      @base_props = base_props
      @automation = automation
      @tools = tools
      @triggers = triggers
    end

    def payload
      @base_props.merge(automation: @automation, tools: @tools, triggers: @triggers)
    end
  end

  # GET /:owner/:repo/agents/automations
  def index
    title = "Automations · #{current_repository.name_with_display_owner}"
    automations = load_automations
    user = T.must(current_user)
    payload = IndexPayload.new(base_payload_props(user), automations: automations)

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/automations/new
  def new
    user = T.must(current_user)
    title = "New Automation · #{current_repository.name_with_display_owner}"
    tools, triggers = load_tools_and_triggers
    payload = NewPayload.new(base_payload_props(user), tools:, triggers:)

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/automations/:id/edit
  def edit
    user = T.must(current_user)
    automation_id = params[:id]
    return render_404 unless automation_id.present?

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :automations_controller_edit,
      user_session: user_session
    )

    automation = load_automation(automation_id:, token:)
    return render_404 if automation.nil?

    tools, triggers = load_tools_and_triggers
    payload = EditPayload.new(base_payload_props(user), automation:, tools:, triggers:)

    title = "Edit #{automation["name"]} · #{current_repository.name_with_display_owner}"

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  # GET /:owner/:repo/agents/automations/:id
  def show
    user = T.must(current_user)
    automation_id = params[:id]
    return render_404 unless automation_id.present?

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :automations_controller_show,
      user_session: user_session
    )

    automation = load_automation(automation_id:, token:)
    return render_404 if automation.nil?

    tasks = load_tasks(automation_id:, token:)

    payload = ShowPayload.new(base_payload_props(user), tasks:, automation:)

    title = "#{automation["name"]} · #{current_repository.name_with_display_owner}"

    respond_to do |format|
      format.html do
        render_react_html(
          title: title,
          payload: payload,
          app_name: self.class.react_bundle_name,
          page_data: PAGE_DATA,
          turbo: TURBO_CONFIG,
        )
      end
      format.json do
        render_react_json(title: title, payload: payload)
      end
    end
  end

  private

  def require_automations_visible
    render_404 unless automations_visible_for_current_user?
  end

  def load_automation(automation_id:, token:)
    user = T.must(current_user)
    capi = Copilot::User.copilot_api(
      user:,
      integration_id: CopilotAPI::COPILOT_SWE_AGENT,
      token:,
    )
    response = capi.get_swe_agent_automation(
      repo_owner: current_repository.owner.display_login,
      repo_name: current_repository.name,
      automation_id: automation_id,
    )
    result = response.is_a?(ConcurrentFaraday::FutureResponse) ? response.value : response
    return nil unless result.is_a?(Hash)

    result
  rescue CopilotAPI::NotFoundError
    nil
  end

  def load_tasks(automation_id:, token:)
    user = T.must(current_user)
    begin
      tasks = CopilotSessions::TaskApi::TaskList.for_automation(
        user:,
        token:,
        automation_id:,
        page_size: 10,
      ).tasks
      tasks.map(&:to_h)
    rescue => e
      Failbot.report(e, "Failed to load tasks for automation #{automation_id} in repository #{current_repository.id}")
      []
    end
  end

  def load_automations
    user = T.must(current_user)

    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :automations_controller_index,
      user_session: user_session
    )
    capi = Copilot::User.copilot_api(
      user:,
      integration_id: CopilotAPI::COPILOT_SWE_AGENT,
      token:
    )
    response = capi.get_swe_agent_automations(
      repo_owner: current_repository.owner.display_login,
      repo_name: current_repository.name,
    )
    result = response.is_a?(ConcurrentFaraday::FutureResponse) ? response.value : response
    return [] unless result.is_a?(Hash)

    result.fetch("results", [])
  rescue => e
    Failbot.report(e, "Failed to load automations in repository #{current_repository.id}")
    []
  end

  def load_tools_and_triggers
    user = T.must(current_user)
    token = CopilotSessions::CopilotApiToken.get_encrypted(
      user:,
      entry_point: :automations_controller_form,
      user_session: user_session
    )
    capi = Copilot::User.copilot_api(
      user:,
      integration_id: CopilotAPI::COPILOT_SWE_AGENT,
      token:
    )
    tools_response = capi.get_automations_tools
    triggers_response = capi.get_automations_triggers
    tools_result = tools_response.is_a?(ConcurrentFaraday::FutureResponse) ? tools_response.value : tools_response
    triggers_result = triggers_response.is_a?(ConcurrentFaraday::FutureResponse) ? triggers_response.value : triggers_response

    tools = tools_result.is_a?(Hash) ? tools_result.fetch("results", []) : []
    triggers = triggers_result.is_a?(Hash) ? triggers_result.fetch("results", []) : []

    [tools, triggers]
  rescue => e
    Failbot.report(e, "Failed to load automation tools/triggers in repository #{current_repository.id}")
    [[], []]
  end
end
