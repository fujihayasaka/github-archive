# typed: strict
# frozen_string_literal: true

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
            Copilot::Types::Models::Publisher::Gemini
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false unless entity.feature_flag_enabled?(:copilot_tulip, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_tulip_pro) do
              case entity
              when Copilot::User
                return false if entity.has_limited_access?

                if entity.feature_flag_enabled?(:copilot_tulip_pro, default: false)
                  true
                else
                  entity.has_pro_plus_access? || entity.has_max_access? || entity.has_cfe_access?
                end
              when Copilot::Organization
                return true if entity.copilot_plan_enterprise?
                return true if entity.copilot_plan_business? && entity.feature_flag_enabled?(:copilot_tulip_pro, default: false)

                false
              when Copilot::Business
                true
              end
            end
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_tulip_ga, default: false)
          end

          # only allow editing for cfe businesses unless pro/cfb flag is enabled
          sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
          def editable_by_business?(copilot_business)
            super && (copilot_business.feature_flag_enabled?(:copilot_tulip_pro, default: false) || copilot_business.can_access_copilot_enterprise_models?)
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
