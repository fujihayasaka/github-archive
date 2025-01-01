# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Ofm
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
            "o_fm"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI o4-mini"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://docs.github.com/en/copilot/using-github-copilot/ai-models/using-openai-o4-mini-in-github-copilot"
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return false if user.has_limited_access?
              return user.has_cfi_access? || user.has_cfb_access? || user.has_cfe_access?
            end

            true
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            true
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
              user.business_copilot_provider_ea_user_fallback_policy(:o_fm) || "unconfigured"
            end
          end

          sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
          def propagate_business_updates?(business, org)
            true
          end

          sig { override.returns(Symbol) }
          def instrumentation_key
            :ofm_setting
          end

          sig { override.returns(Symbol) }
          def twirp_key
            :ofm_setting
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
              enabled: :OFM_ENABLED,
              disabled: :OFM_DISABLED,
              no_policy: :OFM_NO_POLICY,
              unconfigured: :OFM_UNCONFIGURED,
              unknown: :OFM_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OFM::OFM_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OFM::OFM_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OFM::OFM_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OFM::OFM_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OFM::OFM_INVALID
            }
          end
        end
      end
    end
  end
end
