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

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            user.business_copilot_provider_ea_user_fallback_policy(:chat_setting) || "unconfigured"
          end
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
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
