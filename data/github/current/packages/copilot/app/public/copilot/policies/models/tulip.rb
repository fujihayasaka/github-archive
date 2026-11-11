# typed: strict
# frozen_string_literal: true

# DEPRECATED

module Copilot
  module Policies
    module Models
      class Tulip
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "tulip"
          end

          sig { override.returns(String) }
          def display_name
            "Google Gemini 3 Pro"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://docs.github.com/en/copilot/reference/ai-models/model-hosting#google-models"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Google
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false if entity.feature_flag_enabled?(:copilot_tulip_policy_deprecated, default: false)
            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_tulip_ga, default: false)
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
              enabled: :TULIP_ENABLED,
              disabled: :TULIP_DISABLED,
              no_policy: :TULIP_NO_POLICY,
              unconfigured: :TULIP_UNCONFIGURED,
              unknown: :TULIP_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Tulip::TULIP_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Tulip::TULIP_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Tulip::TULIP_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Tulip::TULIP_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Tulip::TULIP_INVALID,
            }
          end
        end
      end
    end
  end
end
