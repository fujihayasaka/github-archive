# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Desktop
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
          "desktop"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot in GitHub Desktop"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/using-copilot-in-github-desktop"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:copilot_desktop, default: false)

          if entity.sorbet_class == ::User
            user = T.cast(entity, Copilot::User)
            return false if user.has_limited_access? && !entity.feature_flag_enabled?(:copilot_free_desktop, default: false)
          end

          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          !entity.feature_flag_enabled?(:copilot_desktop_no_preview_badge, default: false)
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            user.business_copilot_provider_ea_user_fallback_policy(:desktop) || "unconfigured"
          end
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotForBusinessMailer.desktop_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotForBusinessMailer.desktop_disabled_for_user(org, user).deliver_later
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
            enabled: :DESKTOP_ENABLED,
            disabled: :DESKTOP_DISABLED,
            no_policy: :DESKTOP_NO_POLICY,
            unconfigured: :DESKTOP_UNCONFIGURED,
            unknown: :DESKTOP_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::DESKTOP::DESKTOP_INVALID
          }
        end
      end
    end
  end
end
