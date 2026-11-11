# typed: strict
# frozen_string_literal: true

module AgenticApp
  module EnterpriseOptInDependency
    extend T::Helpers

    requires_ancestor { Kernel }

    sig { params(agentic_app: AgenticApp, target: T.any(Business, User)).returns(T::Boolean) }
    def enterprise_opted_in?(agentic_app, target)
      ai_agent_blockable_by_enterprise_policy = Apps::Privileged.capable?(:ai_agent_blockable_by_enterprise_policy, app: agentic_app.integration)
      return true unless ai_agent_blockable_by_enterprise_policy

      business = target.is_a?(Business) ? target : business_for(target)

      # if there is no enterprise/business, default to opted in as there is no policy to enforce
      return true unless business

      business.config.enabled?(opt_in_configuration_name(agentic_app))
    end

    sig { params(target: User).returns(T::Boolean) }
    def has_copilot_enterprise_license?(target)
      return true if target.feature_flag_enabled?(:agentshq_bypass_copilot_enterprise, default: false)

      if target.is_a?(Organization)
        copilot_organization = Copilot::Organization.new(target)
        return true if copilot_organization.copilot_plan_enterprise?
        return copilot_organization.copilot_plan_business?
      end

      true
    end

    sig { params(agentic_app: AgenticApp, business: Business, actor: User).void }
    def opt_in_enterprise!(agentic_app, business, actor)
      business.config.enable!(opt_in_configuration_name(agentic_app), actor)

      payload = { business: business, user: actor }
      name = "#{agentic_app.slug}.optin"

      GitHub.instrument(name, payload)
      GlobalInstrumenter.instrument(name, payload)
    end

    sig { params(agentic_app: AgenticApp, business: Business, actor: User).void }
    def opt_out_enterprise!(agentic_app, business, actor)
      business.config.disable!(opt_in_configuration_name(agentic_app), actor)

      payload = { business: business, user: actor }
      name = "#{agentic_app.slug}.optout"

      GitHub.instrument(name, payload)
      GlobalInstrumenter.instrument(name, payload)
    end

    sig { params(target: User).returns(T.nilable(Business)) }
    def business_for(target)
      business =
        case target
        when Organization
          target.configuration_owner if target.configuration_owner.is_a?(Business)
        when User
          # For EMUs, the configuration owner is still GitHub, so we have to call
          # the business directly.
          target.enterprise_managed_business if target.is_enterprise_managed?
        else
          T.absurd(target)
        end
    end

    private

    # Hard code the configuration names for each agentic app so that they are
    # stable even if the slug changes.
    sig { params(agentic_app: AgenticApp).returns(String) }
    def opt_in_configuration_name(agentic_app)
      case agentic_app
      when AgenticApp::ClaudeAgent
        "claude_agent_enterprise_opt_in"
      when AgenticApp::CodexAgent
        "codex_agent_enterprise_opt_in"
      when AgenticApp::CopilotCodeReviewAgent
        "copilot_code_review_agent_enterprise_opt_in"
      when AgenticApp::MockAgent
        "#{agentic_app.slug}_enterprise_opt_in"
      else
        raise "Unknown agentic app: #{agentic_app.slug}"
      end
    end
  end
end
