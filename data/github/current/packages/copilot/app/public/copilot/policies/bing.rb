# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Bing
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "bing_github_chat"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot can search the web"
        end

        # actually a privacy statement
        sig { override.returns(String) }
        def documentation_url
          "https://privacy.microsoft.com/en-us/privacystatement"
        end

        sig { override.params(copilot_business: Copilot::Business).returns(PolicyDescription) }
        def business_setting_description(copilot_business)
          shared_description
        end

        sig { override.params(copilot_organization: Copilot::Organization).returns(PolicyDescription) }
        def organization_setting_description(copilot_organization)
          shared_description
        end

        sig { override.params(copilot_user: Copilot::User).returns(PolicyDescription) }
        def user_setting_description(copilot_user)
          shared_description
        end


        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return value(user) if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :github_chat_bing_access_setting
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :bing_setting
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          !GitHub.multi_tenant_enterprise?
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:no_policy]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:disabled]
        end

        sig { override.params(copilot_user: Copilot::User).returns(String) }
        def user_default_value(copilot_user)
          config_values[:enabled]
        end

        private

        sig do override.returns({
            enabled: Symbol,
            disabled: Symbol,
            no_policy: Symbol,
            unconfigured: Symbol,
            unknown: Symbol
          })
        end
        def instrumentation_symbols
          {
            enabled: :GITHUB_CHAT_BING_ACCESS_ENABLED,
            disabled: :GITHUB_CHAT_BING_ACCESS_DISABLED,
            no_policy: :GITHUB_CHAT_BING_ACCESS_NO_POLICY,
            unconfigured: :GITHUB_CHAT_BING_ACCESS_UNCONFIGURED,
            unknown: :GITHUB_CHAT_BING_ACCESS_UNKNOWN
          }
        end

        sig do override.returns({
            enabled: Integer,
            disabled: Integer,
            no_policy: Integer,
            unconfigured: Integer,
            invalid: Integer
          })
        end
        def twirp_values
          {
            enabled: MonolithTwirp::Copilot::Users::V1::Bing::BING_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::Bing::BING_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::Bing::BING_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::Bing::BING_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::Bing::BING_INVALID
          }
        end

        sig { returns(PolicyDescription) }
        def shared_description
          [
            "Copilot can answer questions about new trends and give improved answers, via Bing. See",
            PolicyDescriptionChunk.new(text: "Microsoft's Privacy Statement.", href: documentation_url)
          ]
        end
      end
    end
  end
end
