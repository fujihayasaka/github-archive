# typed: strict
# frozen_string_literal: true

# OpenAI GPT 4.1 is the new base model for Copilot.
# For CfI users this means that this policy is always enabled.
# However, some customers wanted to delay the migration and continue
# using 4o. As a result, we flag in customers to allow them to configure
# 4.1. This logic can be removed when we fully migrate.
# See more: https://github.com/github/copilot/issues/18215

module Copilot
  module Policies
    module Models
      class Ofo
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
            "ofo"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-4.1"
          end

          # no docs url for this one
          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/openai-gpt-41"
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
            return "enabled" unless user.any_business_or_org_has_fsi_enabled?

            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)

            # the inherited value will be one of enabled or disabled (or nil)
            if !inherited_policy.nil?
              inherited_policy
            else
              # if the inherited value is nil, first try and do the ea fallback.
              # if there is no fallback, the policy is unconfigured
              user.business_copilot_provider_ea_user_fallback_policy(:ofo) || "unconfigured"
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
              enabled: :OFO_ENABLED,
              disabled: :OFO_DISABLED,
              no_policy: :OFO_NO_POLICY,
              unconfigured: :OFO_UNCONFIGURED,
              unknown: :OFO_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OFO::OFO_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OFO::OFO_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OFO::OFO_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OFO::OFO_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OFO::OFO_INVALID
            }
          end
        end
      end
    end
  end
end
