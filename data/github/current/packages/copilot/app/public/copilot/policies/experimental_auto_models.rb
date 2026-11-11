# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class ExperimentalAutoModels
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::User::Mutable

        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        sig { override.returns(String) }
        def config_name
          "experimental_auto_models"
        end

        sig { override.returns(String) }
        def display_name
          "Evaluation models in Copilot auto model selection"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/concepts/auto-model-selection"
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "If enabled, you may be served",
            PolicyDescriptionChunk.new(
              text: "evaluation models",
              href: "https://docs.github.com/en/copilot/reference/ai-models/supported-models#evaluation-models",
            ),
            "through",
            PolicyDescriptionChunk.new(
              text: "Copilot Auto model selection",
              href: documentation_url,
            ),
            ".",
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.sorbet_class == ::User
          return false unless entity.feature_flag_enabled?(:copilot_experimental_auto_models, default: false)

          T.cast(entity, Copilot::User).has_cfi_access?
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "no_policy" unless available_for?(user)

          user_value = value(user)
          return "enabled" if user_value == "unconfigured"

          user_value
        end

        sig { override.returns(T::Boolean) }
        def skip_business_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_organization_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
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
            enabled: :EXPERIMENTAL_AUTO_MODELS_ENABLED,
            disabled: :EXPERIMENTAL_AUTO_MODELS_DISABLED,
            no_policy: :EXPERIMENTAL_AUTO_MODELS_NO_POLICY,
            unconfigured: :EXPERIMENTAL_AUTO_MODELS_UNCONFIGURED,
            unknown: :EXPERIMENTAL_AUTO_MODELS_UNKNOWN,
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
            enabled: MonolithTwirp::Copilot::Users::V1::ExperimentalAutoModels::EXPERIMENTAL_AUTO_MODELS_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::ExperimentalAutoModels::EXPERIMENTAL_AUTO_MODELS_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::ExperimentalAutoModels::EXPERIMENTAL_AUTO_MODELS_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::ExperimentalAutoModels::EXPERIMENTAL_AUTO_MODELS_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::ExperimentalAutoModels::EXPERIMENTAL_AUTO_MODELS_INVALID,
          }
        end
      end
    end
  end
end
