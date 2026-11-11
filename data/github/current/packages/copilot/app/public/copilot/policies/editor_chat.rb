# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class EditorChat
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable
        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "chat_enabled"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Chat in the IDE"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/how-tos/use-chat/use-chat-in-ide"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Organizations can use Copilot Chat for code editors."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organizations will have access to #{display_name}.",
            PolicyDescriptionChunk.new(text: "Learn more about Copilot in your editor.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: "GitHub #{display_name}", href: documentation_url),
            "to explain a piece of code, propose bug fixes, or generate unit tests in a chat interface from your editor."
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          super && !copilot_user.has_limited_access?
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

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotForBusinessMailer.chat_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotForBusinessMailer.chat_disabled_for_user(org, user).deliver_later
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :editor_chat_setting
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :editor_chat_setting
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          copilot_business.copilot_standalone? ? config_values[:unconfigured] : config_values[:enabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:enabled]
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
            enabled: :EDITOR_CHAT_ENABLED,
            disabled: :EDITOR_CHAT_DISABLED,
            no_policy: :EDITOR_CHAT_NO_POLICY,
            unconfigured: :EDITOR_CHAT_UNCONFIGURED,
            unknown: :EDITOR_CHAT_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_NO_POLICY,
            unconfigured: MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::EditorChat::EDITOR_CHAT_INVALID
          }
        end
      end
    end
  end
end
