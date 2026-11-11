# typed: strict
# frozen_string_literal: true

# The DotcomChat policy controls the availability of Copilot Chat in GitHub.com. This policy is not something that is directly configurable
# by end users, and is instead controlled via the "Copilot in GitHub.com" policy. This policy is hidden from business and organization
# settings pages, and is only viewable by users.

module Copilot
  module Policies
    class DotcomChat
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
          "dotcom_chat"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Chat in GitHub.com"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-chat-in-github/using-github-copilot-chat-in-githubcom"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          []
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          []
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          feature_sentence = T.let([
            "You can use #{display_name}",
            user.has_knowledge_bases? ? "knowledge base search" : nil,
          ].compact.to_sentence, String)

          [
            "#{feature_sentence}. Preview features are only available for paid licenses.",
            PolicyDescriptionChunk.new(text: "Learn more about Copilot in GitHub.com", href: documentation_url),
            "."
          ]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          false
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          false
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          true
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
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
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :github_chat_setting
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
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
            enabled: :GITHUB_CHAT_ENABLED,
            disabled: :GITHUB_CHAT_DISABLED,
            no_policy: :GITHUB_CHAT_NO_POLICY,
            unconfigured: :GITHUB_CHAT_UNCONFIGURED,
            unknown: :GITHUB_CHAT_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::DotcomChat::DOTCOM_CHAT_INVALID
          }
        end
      end
    end
  end
end
