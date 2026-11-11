# typed: strict
# frozen_string_literal: true

# DEPRECATED

module Copilot
  module Policies
    module Models
      class Obmb
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "obmb"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-5"
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
            return false if entity.feature_flag_enabled?(:copilot_obmb_policy_deprecated, default: false)
            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
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
              enabled: :OBMB_ENABLED,
              disabled: :OBMB_DISABLED,
              no_policy: :OBMB_NO_POLICY,
              unconfigured: :OBMB_UNCONFIGURED,
              unknown: :OBMB_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OBMB::OBMB_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OBMB::OBMB_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OBMB::OBMB_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OBMB::OBMB_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OBMB::OBMB_INVALID
            }
          end
        end
      end
    end
  end
end
