# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Antman
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "antman"
          end

          sig { override.returns(String) }
          def display_name
            # TODO: Update when using breakglass policy
            "Placeholder model: Antman"
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
            # This is a template for a free model. DOUBLE CHECK THIS BEFORE USING IT
            return false unless entity.feature_flag_enabled?(:copilot_antman, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_antman_pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_antman_ga, default: false)
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
              enabled: :ANTMAN_ENABLED,
              disabled: :ANTMAN_DISABLED,
              no_policy: :ANTMAN_NO_POLICY,
              unconfigured: :ANTMAN_UNCONFIGURED,
              unknown: :ANTMAN_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Antman::ANTMAN_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Antman::ANTMAN_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Antman::ANTMAN_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Antman::ANTMAN_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Antman::ANTMAN_INVALID,
            }
          end

        end
      end
    end
  end
end
