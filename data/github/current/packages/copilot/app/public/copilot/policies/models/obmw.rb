# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Obmw
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "obmw"
          end

          sig { override.returns(String) }
          def display_name
            "OpenAI GPT-5 mini"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-gpt5mini"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::OpenAI
          end


          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            true
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
            false
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
          def effective_value(user, all_policies = nil)
            if user.has_cfi_access?
              return user.feature_flag_enabled?(:copilot_api_default_model_gpt5mini, default: false) ? "enabled" : value(user)
            end

            super
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
              enabled: :OBMW_ENABLED,
              disabled: :OBMW_DISABLED,
              no_policy: :OBMW_NO_POLICY,
              unconfigured: :OBMW_UNCONFIGURED,
              unknown: :OBMW_UNKNOWN
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
              enabled: MonolithTwirp::Copilot::Users::V1::OBMW::OBMW_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::OBMW::OBMW_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::OBMW::OBMW_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::OBMW::OBMW_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::OBMW::OBMW_INVALID
            }
          end
        end
      end
    end
  end
end
