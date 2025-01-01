# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class O3
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
            "o3"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI o3-mini"
          end

          # no docs url for this one
          sig { override.returns(String) }
          def documentation_url
            ""
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
            return "enabled" if user.has_ci_access?

            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)

            # the inherited value will be one of enabled or disabled (or nil)
            if !inherited_policy.nil?
              inherited_policy
            else
              # if the inherited value is nil, first try and do the ea fallback.
              # if there is no fallback, the policy is unconfigured
              user.business_copilot_provider_ea_user_fallback_policy(:o3) || "unconfigured"
            end
          end

          sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
          def propagate_business_updates?(business, org)
            true
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
              enabled: :O3_ENABLED,
              disabled: :O3_DISABLED,
              no_policy: :O3_NO_POLICY,
              unconfigured: :O3_UNCONFIGURED,
              unknown: :O3_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::O3::O3_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::O3::O3_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::O3::O3_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::O3::O3_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::O3::O3_INVALID
            }
          end
        end
      end
    end
  end
end
