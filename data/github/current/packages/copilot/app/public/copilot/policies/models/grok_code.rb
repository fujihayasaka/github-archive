# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class GrokCode
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "grok_code"
          end

          sig { override.returns(String) }
          def display_name
            "xAI Grok Code Fast 1"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/xai-models"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::XAI
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Free)
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
          def effective_value(user, all_policies = nil)
            if user.has_cfi_access? && available_for?(user)
              if user.feature_flag_enabled?(:all_models_enabled_for_ci, default: false) || user.has_limited_access?
                return "enabled"
              end
            end

            super
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
          end

          sig { override.returns(Symbol) }
          def instrumentation_key
            :grok_setting
          end

          sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
          def business_setting_description(business)
            [
              "If enabled, your organizations will be permitted to access and send data to #{display_name}.",
              PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
            ]
          end

          sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
          def organization_setting_description(org)
            [
              "If enabled, members of this organization can access and send data to #{display_name}.",
              PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
            ]
          end

          sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
          def user_setting_description(user)
            [
              "If enabled, you can access and send data to #{display_name}.",
              PolicyDescriptionChunk.new(text: "Learn more about how GitHub Copilot serves #{display_name}.", href: documentation_url)
            ]
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
              enabled: :GROK_CODE_ENABLED,
              disabled: :GROK_CODE_DISABLED,
              no_policy: :GROK_CODE_NO_POLICY,
              unconfigured: :GROK_CODE_UNCONFIGURED,
              unknown: :GROK_CODE_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::GrokCode::GROK_CODE_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::GrokCode::GROK_CODE_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::GrokCode::GROK_CODE_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::GrokCode::GROK_CODE_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::GrokCode::GROK_CODE_INVALID
            }
          end
        end
      end
    end
  end
end
