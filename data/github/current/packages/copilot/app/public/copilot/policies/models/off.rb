# typed: strict
# frozen_string_literal: true

# DEPRECATED

module Copilot
  module Policies
    module Models
      class Off
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "o_ff"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-4.5 model"
          end

          # no docs
          sig { override.returns(String) }
          def documentation_url
            ""
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::OpenAI
          end

          sig { override.returns(T.nilable(Copilot::Types::Models::Category)) }
          def category
            nil
          end

          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def viewable_by_business?(copilot_business)
            false
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false if entity.feature_flag_enabled?(:copilot_o_ff_policy_deprecated, default: false)

            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Enterprise, min_cfi_plan: Copilot::Plans::CFI::ProPlus)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
          end

          sig { override.returns(Symbol) }
          def instrumentation_key
            :off_setting
          end

          sig { override.returns(Symbol) }
          def twirp_key
            :off_setting
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
              enabled: :OFF_ENABLED,
              disabled: :OFF_DISABLED,
              no_policy: :OFF_NO_POLICY,
              unconfigured: :OFF_UNCONFIGURED,
              unknown: :OFF_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OFF::OFF_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OFF::OFF_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OFF::OFF_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OFF::OFF_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OFF::OFF_INVALID
            }
          end
        end
      end
    end
  end
end
