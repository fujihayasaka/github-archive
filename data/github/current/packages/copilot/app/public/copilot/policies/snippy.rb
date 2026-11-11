# typed: strict
# frozen_string_literal: true

# We call this snippy so that it isn't confusing to have public code suggestions enabled meaning public code
# suggestions are blocked. If snippy is enabled, we snip out the public code!

module Copilot
  module Policies
    class Snippy
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        # we actually want this to be least restrictive, since most restricting blocking (snippy enabled)
        # would mean least restrictive enablement
        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::LeastRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "public_code_suggestions"
        end

        sig { override.returns(String) }
        def display_name
          "Suggestions matching public code"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/how-tos/manage-your-account/manage-policies#enabling-or-disabling-suggestions-matching-public-code"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "GitHub Copilot can allow or block",
            PolicyDescriptionChunk.new(text: "code suggestions", href: Copilot::CFB_PUBLIC_CODE_SUGGESTIONS_DOCS),
            "matching public code."
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["Copilot can allow or block suggestions matching public code."]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          if user.is_enterprise_managed? || user.has_cfb_access? || user.has_copilot_standalone_business?
            [
                "GitHub Copilot can provide you with details about matching code when you accept such suggestions.",
                PolicyDescriptionChunk.new(text: "Learn more", href: documentation_url),
                "."
            ]
          else
            [
              "Copilot can allow or block suggestions matching public code. Learn more about",
              PolicyDescriptionChunk.new(text: "code suggestions", href: documentation_url),
              "."
            ]
          end
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
          if user.has_cfi_access?
            user_value = value(user)
            # unconfigured is no longer a valid state, so we treat it as allowed
            return "allowed" if user_value == "unconfigured"
            return user_value
          end

          # inherited value from org or business
          # (skip fallback since we need to map enabled/disabled to blocked/allowed)
          inherited_policy = user_inherited_policy(user, all_policies, skip_ea_fallback: true)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            fallback_value = business_copilot_provider_ea_user_fallback_policy(user)

            # need to map to actual value here
            unless fallback_value.nil?
              if fallback_value == "enabled"
                return "blocked"
              else
                return "allowed"
              end
            end

            # otherwise return allowed (new default value)
            "allowed"
          end
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :snippy_setting
        end

        sig do override.returns({
            enabled: String,
            disabled: String,
            no_policy: String,
            unconfigured: String,
          })
        end
        def config_values
          {
            enabled: "blocked",
            disabled: "allowed",
            no_policy: "no_policy",
            unconfigured: "unconfigured",
          }
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :snippy_setting
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:disabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:disabled]
        end

        sig { override.params(copilot_user: Copilot::User).returns(String) }
        def user_default_value(copilot_user)
          config_values[:disabled]
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
            enabled: :SNIPPY_ENABLED,
            disabled: :SNIPPY_DISABLED,
            no_policy: :SNIPPY_NO_POLICY,
            unconfigured: :SNIPPY_UNCONFIGURED,
            unknown: :SNIPPY_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_NO_POLICY,
            unconfigured: MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::Snippy::SNIPPY_INVALID
          }
        end
      end
    end
  end
end
