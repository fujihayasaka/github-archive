# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Captainamerica
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "captainamerica"
          end

          sig { override.returns(String) }
          def display_name
            # TODO: Update when using breakglass policy
            "Placeholder model: Captain America"
          end

          sig { override.returns(String) }
          def documentation_url
            # TODO: Update when using breakglass policy
            "https://gh.io/placeholder"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            # TODO: Update when using breakglass policy
            Copilot::Types::Models::Publisher::Tented
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            # This is a template for a pro plus and cfe users only model. DOUBLE CHECK THIS BEFORE USING IT
            return false unless entity.feature_flag_enabled?(:copilot_captainamerica, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_captainamerica_pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_captainamerica_ga, default: false)
          end

          private

          sig do
            override.returns({
              enabled: Symbol,
              disabled: Symbol,
              no_policy: Symbol,
              unconfigured: Symbol,
              unknown: Symbol,
            })
          end
          def instrumentation_symbols
            {
              enabled: :CAPTAINAMERICA_ENABLED,
              disabled: :CAPTAINAMERICA_DISABLED,
              no_policy: :CAPTAINAMERICA_NO_POLICY,
              unconfigured: :CAPTAINAMERICA_UNCONFIGURED,
              unknown: :CAPTAINAMERICA_UNKNOWN,
            }
          end

          sig do
            override.returns({
              enabled: Integer,
              disabled: Integer,
              no_policy: Integer,
              unconfigured: Integer,
              invalid: Integer,
            })
          end
          def twirp_values
            {
              enabled: MonolithTwirp::Copilot::Users::V1::Captainamerica::CAPTAINAMERICA_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Captainamerica::CAPTAINAMERICA_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Captainamerica::CAPTAINAMERICA_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Captainamerica::CAPTAINAMERICA_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Captainamerica::CAPTAINAMERICA_INVALID,
            }
          end

        end
      end
    end
  end
end
