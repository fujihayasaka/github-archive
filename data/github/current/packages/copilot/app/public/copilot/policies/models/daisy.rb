# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Daisy
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "daisy"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Sonnet 4.5"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-anthropic"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Anthropic
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
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
              enabled: :DAISY_ENABLED,
              disabled: :DAISY_DISABLED,
              no_policy: :DAISY_NO_POLICY,
              unconfigured: :DAISY_UNCONFIGURED,
              unknown: :DAISY_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Daisy::DAISY_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Daisy::DAISY_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Daisy::DAISY_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Daisy::DAISY_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Daisy::DAISY_INVALID,
            }
          end
        end
      end
    end
  end
end
