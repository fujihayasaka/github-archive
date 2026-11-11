# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Lotus
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "lotus"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Opus 4.5"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-claude-opus"
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
              enabled: :LOTUS_ENABLED,
              disabled: :LOTUS_DISABLED,
              no_policy: :LOTUS_NO_POLICY,
              unconfigured: :LOTUS_UNCONFIGURED,
              unknown: :LOTUS_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Lotus::LOTUS_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Lotus::LOTUS_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Lotus::LOTUS_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Lotus::LOTUS_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Lotus::LOTUS_INVALID,
            }
          end
        end
      end
    end
  end
end
