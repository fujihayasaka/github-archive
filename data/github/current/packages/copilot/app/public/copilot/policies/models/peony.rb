# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Peony
        class << self
          include Copilot::PolicyInterface

          include Copilot::Policies::Concerns::Core
          include Copilot::Policies::Concerns::Mutable
          include Copilot::Policies::Concerns::Model::Serializable

          include Copilot::Policies::Concerns::Instrumentable
          include Copilot::Policies::Concerns::Twirpable
          include Copilot::Policies::Concerns::Ruleable

          include Copilot::Policies::Concerns::User::Cacheable

          sig { override.returns(String) }
          def config_name
            "peony"
          end

          sig { override.returns(String) }
          def display_name
            "Raptor mini"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-openai-fine-tuned-by-microsoft"
          end

          sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
          def business_setting_description(business)
            []
          end

          sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
          def organization_setting_description(org)
            []
          end

          sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
          def user_setting_description(user)
            [
              "You can use the latest #{display_name} model.",
              PolicyDescriptionChunk.new(text: "Learn more about how GitHub Copilot serves #{display_name}.", href: documentation_url)
            ]
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Microsoft
          end

          sig { override.returns(T.nilable(Copilot::Types::Models::Category)) }
          def category
            nil
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false unless entity.is_a?(Copilot::User)

            copilot_plan_at_least?(entity, min_cfb_plan: nil, min_cfi_plan: Copilot::Plans::CFI::Free)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:copilot_peony_ga, default: false)
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
          def effective_value(user, all_policies = nil)
            if user.has_cfi_access? && available_for?(user)
              if user.feature_flag_enabled?(:all_models_enabled_for_ci, default: false) || user.has_limited_access?
                return "enabled"
              end
            end

            return "disabled" unless available_for?(user)
            value(user)
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
              enabled: :PEONY_ENABLED,
              disabled: :PEONY_DISABLED,
              no_policy: :PEONY_NO_POLICY,
              unconfigured: :PEONY_UNCONFIGURED,
              unknown: :PEONY_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Peony::PEONY_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Peony::PEONY_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Peony::PEONY_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Peony::PEONY_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Peony::PEONY_INVALID,
            }
          end
        end
      end
    end
  end
end
