# typed: strict
# frozen_string_literal: true

# DEPRECATED

module Copilot
  module Policies
    module Models
      class Ofct
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "ofct"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-5-Codex"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-openai"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::OpenAI
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            return false if entity.feature_flag_enabled?(:copilot_ofct_policy_deprecated, default: false)

            copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            !entity.feature_flag_enabled?(:ofct_ga, default: false)
          end

          sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
          def business_setting_description(business)
            [
              "If enabled, organizations can access the latest #{display_name} model in Copilot.",
              PolicyDescriptionChunk.new(
                text: "Learn how GitHub Copilot serves #{display_name} and confirm compatibility with your team's IDEs in our documentation.",
                href: documentation_url
              )
            ]
          end

          sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
          def organization_setting_description(org)
            [
              "If enabled, members of this organization will have access to the latest #{display_name} model.",
              PolicyDescriptionChunk.new(
                text: "Learn how GitHub Copilot serves #{display_name} and confirm compatibility with your team's IDEs in our documentation.",
                href: documentation_url
              )
            ]
          end

          sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
          def user_setting_description(user)
            [
              "You can use the latest #{display_name} model.",
              PolicyDescriptionChunk.new(
                text: "Learn how GitHub Copilot serves #{display_name} and confirm compatibility with your IDE in our documentation.",
                href: documentation_url
              )
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
              enabled: :OFCT_ENABLED,
              disabled: :OFCT_DISABLED,
              no_policy: :OFCT_NO_POLICY,
              unconfigured: :OFCT_UNCONFIGURED,
              unknown: :OFCT_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OFCT::OFCT_INVALID
            }
          end
        end
      end
    end
  end
end
