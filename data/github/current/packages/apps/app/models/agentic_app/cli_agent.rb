# typed: strict
# frozen_string_literal: true

module AgenticApp
  # Copilot CLI Agent - Global agent for CLI-based coding tasks
  class CliAgent < Base
    sig { override.returns(String) }
    def slug
      "copilot-developer-cli"
    end

    sig { override.returns(String) }
    def display_name
      "Copilot CLI"
    end

    sig { override.returns(String) }
    def display_owner
      "GitHub"
    end

    sig { override.returns(String) }
    def doc_url
      "https://gh.io/copilot-cli"
    end

    sig { override.returns(Symbol) }
    def privileged_app_alias
      :copilot_cli_github_app
    end

    # disallow_feature_flag is required by Base but not used for this agent — access
    # is instead controlled via Vexi feature flags in enabled_for_repository?.
    sig { override.returns(Symbol) }
    def disallow_feature_flag
      :copilot_cli_disallow
    end

    sig { override.returns(Symbol) }
    def policy_feature_flag
      :copilot_cli_remote_control
    end

    sig { override.returns(T::Boolean) }
    def assignable?
      false
    end

    sig { override.returns(T::Boolean) }
    def mentionable?
      false
    end

    sig { override.returns(T::Boolean) }
    def global?
      true
    end

    sig { override.returns(AgenticApp::Group) }
    def group
      AgenticApp::Group::CLI
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def installed_for_target?(target)
      true  # Global agent - always installed
    end

    sig { override.params(target: T.any(User, Organization, Business)).returns(T::Boolean) }
    def can_be_enabled_for?(target)
      true
    end

    sig do
      override.params(
        repo: T.untyped,
        viewer: T.untyped
      ).returns(T::Boolean)
    end
    def enabled_for_repository?(repo, viewer)
      return false if viewer.nil?
      return false unless integration
      return false unless FeatureFlag.vexi.enabled?(:copilot_mission_control_agent_filtering, viewer, default: false)

      copilot_user = Copilot::Public::User.for(viewer)
      return false unless copilot_user.has_copilot_access?

      copilot_user.policy_values[:cli] == "enabled"
    end
  end
end
