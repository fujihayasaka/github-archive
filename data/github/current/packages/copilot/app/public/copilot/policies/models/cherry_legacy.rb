# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class CherryLegacy
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "cherry"
          end

          sig { override.returns(String) }
          def display_name
            # TODO
            "PLACEHOLDER: Cherry Legacy model"
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
            return false unless entity.feature_flag_enabled?(:copilot_cherry_no_registry, default: false)

            progressive_rollout_available_for?(entity, pro_flag: :copilot_cherry_pro_no_registry)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_cherry_no_registry_ga_no_registry, default: false)
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
              enabled: :CHERRY_ENABLED,
              disabled: :CHERRY_DISABLED,
              no_policy: :CHERRY_NO_POLICY,
              unconfigured: :CHERRY_UNCONFIGURED,
              unknown: :CHERRY_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Cherry::CHERRY_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Cherry::CHERRY_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Cherry::CHERRY_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Cherry::CHERRY_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Cherry::CHERRY_INVALID,
            }
          end
        end
      end
    end
  end
end
