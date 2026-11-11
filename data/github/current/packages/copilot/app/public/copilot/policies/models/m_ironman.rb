# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class MIronman
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "m_ironman"
          end

          sig { override.returns(String) }
          def display_name
            "Ironman Placeholder Model"
          end

          sig { override.returns(String) }
          def documentation_url
            ""
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            # This is just a template for a free model. DOUBLE CHECK THIS BEFORE USING IT

            return false unless entity.feature_flag_enabled?(:copilot_m_ironman, default: false)

            true
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:m_ironman_ga, default: false)
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
              enabled: :M_IRONMAN_ENABLED,
              disabled: :M_IRONMAN_DISABLED,
              no_policy: :M_IRONMAN_NO_POLICY,
              unconfigured: :M_IRONMAN_UNCONFIGURED,
              unknown: :M_IRONMAN_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::MIronman::M_IRONMAN_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::MIronman::M_IRONMAN_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::MIronman::M_IRONMAN_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::MIronman::M_IRONMAN_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::MIronman::M_IRONMAN_INVALID
            }
          end
        end
      end
    end
  end
end
