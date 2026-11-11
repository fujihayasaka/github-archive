# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Gtff
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "gtff"
          end

          sig { override.returns(String) }
          def display_name
            "Google Gemini 2.5 Flash"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://docs.github.com/copilot/using-github-copilot/ai-models/using-gemini-flash-in-github-copilot"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Gemini
          end


          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false if entity.feature_flag_enabled?(:copilot_model_deprecate_oct_25, default: false)

            entity.feature_flag_enabled?(:copilot_gtff, default: false)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
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
              enabled: :GTFF_ENABLED,
              disabled: :GTFF_DISABLED,
              no_policy: :GTFF_NO_POLICY,
              unconfigured: :GTFF_UNCONFIGURED,
              unknown: :GTFF_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::GTFF::GTFF_INVALID
            }
          end
        end
      end
    end
  end
end
