# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class MThor
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "m_thor"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-5.1-Codex-Mini"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-openai"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::OpenAI
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false unless entity.feature_flag_enabled?(:copilot_m_thor, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_m_thor_pro) do
              case entity
              when Copilot::User
                return false if entity.has_limited_access?

                if entity.feature_flag_enabled?(:copilot_m_thor_pro, default: false)
                  true
                else
                  entity.has_pro_plus_access? || entity.has_max_access? || entity.has_cfe_access?
                end
              when Copilot::Organization
                return true if entity.copilot_plan_enterprise?
                return true if entity.copilot_plan_business? && entity.feature_flag_enabled?(:copilot_m_thor_pro, default: false)

                false
              when Copilot::Business
                true
              end
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:m_thor_ga, default: false)
          end

          # only allow editing for cfe businesses unless pro/cfb flag is enabled
          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def editable_by_business?(copilot_business)
            super && (copilot_business.feature_flag_enabled?(:copilot_m_thor_pro, default: false) || copilot_business.can_access_copilot_enterprise_models?)
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
              enabled: :M_THOR_ENABLED,
              disabled: :M_THOR_DISABLED,
              no_policy: :M_THOR_NO_POLICY,
              unconfigured: :M_THOR_UNCONFIGURED,
              unknown: :M_THOR_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::MThor::M_THOR_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::MThor::M_THOR_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::MThor::M_THOR_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::MThor::M_THOR_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::MThor::M_THOR_INVALID
            }
          end
        end
      end
    end
  end
end
