# typed: strict
# frozen_string_literal: true

# This policy is used with custom models/fine tuning which won't have any more actors added to it.
# Kept here so that existing users can continue to use the policy without disruption.
# See https://github.slack.com/archives/C06CYDSCSQN/p1755274049351339

module Copilot
  module Policies
    class CustomModels
      class << self # rubocop:disable Style/ClassMethodsDefinitions
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        sig { override.returns(String) }
        def config_name
          "custom_models"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot Fine-tuning"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/copilot/overview-of-github-copilot/about-github-copilot-custom-models"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          if entity.sorbet_class == ::User
            user = T.cast(entity, Copilot::User)
            return false if user.has_limited_access?
          end
          entity.feature_flag_enabled?(:copilot_custom_models, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # this policy reads directly from the configuration
          value(user)
        end

        sig { override.returns(T::Boolean) }
        def hide_from_audit_log?
          true
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :custom_model
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
            enabled: :CUSTOM_MODELS_ENABLED,
            disabled: :CUSTOM_MODELS_DISABLED,
            no_policy: :CUSTOM_MODELS_NO_POLICY,
            unconfigured: :CUSTOM_MODELS_UNCONFIGURED,
            unknown: :CUSTOM_MODELS_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_NO_POLICY,
            unconfigured: MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::CustomModel::CUSTOM_MODEL_INVALID
          }
        end
      end
    end
  end
end
