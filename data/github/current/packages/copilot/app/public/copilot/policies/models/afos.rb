# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Afos
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "afos"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Sonnet 4"
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
            experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro) do
              if entity.sorbet_class == ::User
                user = T.cast(entity, Copilot::User)
                return false if user.has_limited_access?
                return user.has_cfi_access? || user.has_cfb_access? || user.has_cfe_access?
              end

              true
            end
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
              enabled: :AFOS_ENABLED,
              disabled: :AFOS_DISABLED,
              no_policy: :AFOS_NO_POLICY,
              unconfigured: :AFOS_UNCONFIGURED,
              unknown: :AFOS_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::AFOS::AFOS_INVALID
            }
          end
        end
      end
    end
  end
end
