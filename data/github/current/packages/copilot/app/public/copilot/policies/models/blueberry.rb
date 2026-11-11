# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Blueberry
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "blueberry"
          end

          sig { override.returns(String) }
          def display_name
            # TODO
            "PLACEHOLDER: Blueberry model"
          end

          sig { override.returns(String) }
          def documentation_url
            # TODO
            "https://gh.io/placeholder"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            # TODO
            Copilot::Types::Models::Publisher::Tented
          end


          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false unless entity.feature_flag_enabled?(:copilot_blueberry, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_blueberry_pro) do
              case entity
              when Copilot::User
                return false if entity.has_limited_access?

                if entity.feature_flag_enabled?(:copilot_blueberry_pro, default: false)
                  true
                else
                  entity.has_pro_plus_access? || entity.has_max_access? || entity.has_cfe_access?
                end
              when Copilot::Organization
                return true if entity.copilot_plan_enterprise?
                return true if entity.copilot_plan_business? && entity.feature_flag_enabled?(:copilot_blueberry_pro, default: false)

                false
              when Copilot::Business
                true
              end
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_blueberry_ga, default: false)
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
              enabled: :BLUEBERRY_ENABLED,
              disabled: :BLUEBERRY_DISABLED,
              no_policy: :BLUEBERRY_NO_POLICY,
              unconfigured: :BLUEBERRY_UNCONFIGURED,
              unknown: :BLUEBERRY_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Blueberry::BLUEBERRY_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Blueberry::BLUEBERRY_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Blueberry::BLUEBERRY_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Blueberry::BLUEBERRY_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Blueberry::BLUEBERRY_INVALID,
            }
          end
        end
      end
    end
  end
end
