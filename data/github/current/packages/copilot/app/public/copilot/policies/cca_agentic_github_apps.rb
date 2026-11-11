# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CcaAgenticGitHubApps
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable
        include Copilot::Policies::Concerns::Business::Propagatable

        sig { override.returns(String) }
        def config_name
          "cca_agentic_github_apps"
        end

        sig { override.returns(String) }
        def display_name
          "Agent apps"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/agent-apps-docs"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["If enabled, enterprise admins can turn on agentic features provided by GitHub Apps."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["If enabled, organizations can use agentic features provided by GitHub Apps."]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          case entity
          when Copilot::Business
            entity.feature_flag_enabled?(:copilot_cca_agentic_github_apps, default: false)
          when Copilot::Organization
            return false unless entity.copilot_business

            entity.feature_flag_enabled_include_parents?(:copilot_cca_agentic_github_apps, default: false)
          when Copilot::User
            false
          else
            T.absurd(entity)
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          "disabled"
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        private

        sig do
          override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol,
          })
        end
        def instrumentation_symbols
          {
            enabled: :CCA_AGENTIC_GITHUB_APPS_ENABLED,
            disabled: :CCA_AGENTIC_GITHUB_APPS_DISABLED,
            no_policy: :CCA_AGENTIC_GITHUB_APPS_NO_POLICY,
            unconfigured: :CCA_AGENTIC_GITHUB_APPS_UNCONFIGURED,
            unknown: :CCA_AGENTIC_GITHUB_APPS_UNKNOWN,
          }
        end
      end
    end
  end
end
