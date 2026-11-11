# typed: strict
# frozen_string_literal: true

# DEPRECATED

module Copilot
  module Policies
    module Models
      class O1
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "o1"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI o1 models"
          end

          # no docs url for this one
          sig { override.returns(String) }
          def documentation_url
            ""
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::OpenAI
          end


          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def viewable_by_business?(copilot_business)
            false
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false if entity.feature_flag_enabled?(:copilot_o1_policy_deprecated, default: true)
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
              enabled: :O1_ENABLED,
              disabled: :O1_DISABLED,
              no_policy: :O1_NO_POLICY,
              unconfigured: :O1_UNCONFIGURED,
              unknown: :O1_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::O1::O1_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::O1::O1_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::O1::O1_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::O1::O1_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::O1::O1_INVALID
            }
          end
        end
      end
    end
  end
end
