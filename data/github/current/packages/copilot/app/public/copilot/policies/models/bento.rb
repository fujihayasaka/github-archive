# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    module Models
      class Bento
        class << self
          include Copilot::Policies::Concerns::ModelCore

          sig { override.returns(String) }
          def config_name
            "bento"
          end

          sig { override.returns(String) }
          def display_name
            "Anthropic Claude Haiku 4.5"
          end

          sig { override.returns(String) }
          def documentation_url
            "https://gh.io/copilot-anthropic"
          end

          sig { override.returns(Copilot::Types::Models::Publisher) }
          def publisher
            Copilot::Types::Models::Publisher::Anthropic
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def available_for?(entity)
            true
          end

          sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
          def effective_value(user, all_policies = nil)
            if user.has_cfi_access? && user.has_limited_access? && user.feature_flag_enabled?(:haiku_enabled_for_free_users, default: false)
              return "enabled"
            end

            super
          end

          sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
          def preview?(entity)
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
              enabled: :BENTO_ENABLED,
              disabled: :BENTO_DISABLED,
              no_policy: :BENTO_NO_POLICY,
              unconfigured: :BENTO_UNCONFIGURED,
              unknown: :BENTO_UNKNOWN,
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
              enabled: MonolithTwirp::Copilot::Users::V1::Bento::BENTO_ENABLED,
              disabled: MonolithTwirp::Copilot::Users::V1::Bento::BENTO_DISABLED,
              no_policy: MonolithTwirp::Copilot::Users::V1::Bento::BENTO_DISABLED,
              unconfigured: MonolithTwirp::Copilot::Users::V1::Bento::BENTO_UNCONFIGURED,
              invalid: MonolithTwirp::Copilot::Users::V1::Bento::BENTO_INVALID,
            }
          end
        end
      end
    end
  end
end
