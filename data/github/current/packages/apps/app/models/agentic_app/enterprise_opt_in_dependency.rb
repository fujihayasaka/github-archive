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

      # A business is required to enforce opt-in
      return true unless business
      return true unless business.feature_flag_enabled?(:agentshq_policy, default: false)

      business.config.enabled?(opt_in_configuration_name(agentic_app))
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

    private

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

    # Hard code the configuration names for each agentic app so that they are
    # stable even if the slug changes.
    sig { params(agentic_app: AgenticApp).returns(String) }
    def opt_in_configuration_name(agentic_app)
      case agentic_app
      when Apps::Privileged::ClaudeAgent
        "claude_agent_enterprise_opt_in"
      when Apps::Privileged::CodexAgent
        "codex_agent_enterprise_opt_in"
      when AgenticApp::MockAgent
        "#{agentic_app.slug}_enterprise_opt_in"
      else
        raise "Unknown agentic app: #{agentic_app.slug}"
      end
    end
  end
end
