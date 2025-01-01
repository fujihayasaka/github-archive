# typed: strict
# frozen_string_literal: true

# We call this snippy so that it isn't confusing to have public code suggestions enabled meaning public code
# suggestions are blocked. If snippy is enabled, we snip out the public code!

module Copilot
  module Policies
    class Snippy
      class << self
        include Copilot::Policy

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
          "https://docs.github.com/en/copilot/configuring-github-copilot/configuring-github-copilot-settings-on-githubcom#enabling-or-disabling-duplication-detection"
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
          if user.has_cfi_access?
            user_value = value(user)
            # unconfigured is no longer a valid state, so we treat it as allowed
            return "allowed" if user_value == "unconfigured"
            return user_value
          end

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          if !inherited_policy.nil?
            inherited_policy
          else
            # if the inherited value is nil, first try and do the ea fallback.
            # if there is no fallback, the policy is unconfigured
            fallback_value = user.business_copilot_provider_ea_user_fallback_policy(:public_code_suggestions)

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

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
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
