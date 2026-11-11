# typed: strict
# frozen_string_literal: true

class Businesses::AiControls::ThirdPartyAgentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared

  layout "layouts/react_business"

  sig { returns(String) }
  def self.react_bundle_name
    "copilot-agent-plane"
  end

  allow_verified_fetch only: [:update]

  before_action :ensure_not_standalone_copilot_business
  before_action :ensure_ai_controls_enabled
  before_action :ai_controls_write_required
  before_action :dotcom_required
  before_action :ensure_agentshq_policy
  before_action :ensure_this_agentic_app

  sig { void }
  def update
    begin
      json_params = parse_json_params

      # Validate that enable is a boolean (true or false, not truthy/falsy)
      unless [true, false].include?(json_params["enable"])
        return respond_with_react(status: :bad_request)
      end

      if json_params["enable"]
        AgenticApp.opt_in_enterprise!(T.must(this_agentic_app), this_business, current_user)
      else
        AgenticApp.opt_out_enterprise!(T.must(this_agentic_app), this_business, current_user)
      end

      respond_with_react # ok by default
    rescue Yajl::ParseError
      respond_with_react(status: :bad_request)
    end
  end

  private

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ensure_agentshq_policy
    render_404 unless this_business.feature_flag_enabled?(:agentshq_policy, default: false)
  end

  sig { void }
  def ensure_ai_controls_enabled
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ensure_this_agentic_app
    render_404 if this_agentic_app.nil? || T.must(this_agentic_app).global? # do not allow global agents to be toggled.
  end

  sig { returns(T.nilable(AgenticApp::AgentInstance)) }
  memoize def this_agentic_app
    AgenticApp.agent_for_slug(params[:agent_slug])
  end
end
