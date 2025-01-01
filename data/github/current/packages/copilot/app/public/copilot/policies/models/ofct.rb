# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Ofct
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
            "ofct"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-5 Codex"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-openai"
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false unless entity.feature_flag_enabled?(:copilot_ofct, default: false)

            case entity
            when Copilot::User
              return false if entity.has_limited_access?
              # if you have a premiun plan, you can access OFCT if the feature flag is enabled
              return true if entity.has_pro_plus_access? || entity.has_max_access? || entity.has_cfe_access?
              # if you have a pro plan, you can access OFCT if the feature flag is enabled
              return true if (entity.has_pro_access? || entity.has_cfb_access?) && entity.feature_flag_enabled?(:copilot_ofct_pro, default: false)

              # fallback to false
              false
            when Copilot::Organization
              return true if entity.copilot_plan_enterprise?
              return true if entity.copilot_plan_business? && entity.feature_flag_enabled?(:copilot_ofct_pro, default: false)

              # fallback to false
              false
            when Copilot::Business
              true
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:ofct_ga, default: false)
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
          def effective_value(user, all_policies = nil)
            return "disabled" unless available_for?(user)
            return value(user) if user.has_cfi_access?

            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)

            # the inherited value will be one of enabled or disabled (or nil)
            if !inherited_policy.nil?
              inherited_policy
            else
              # if the inherited value is nil, first try and do the ea fallback.
              # if there is no fallback, the policy is unconfigured
              user.business_copilot_provider_ea_user_fallback_policy(:ofct) || "unconfigured"
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
              enabled: :OFCT_ENABLED,
              disabled: :OFCT_DISABLED,
              no_policy: :OFCT_NO_POLICY,
              unconfigured: :OFCT_UNCONFIGURED,
              unknown: :OFCT_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_INVALID
            }
          end
        end
      end
    end
  end
end
