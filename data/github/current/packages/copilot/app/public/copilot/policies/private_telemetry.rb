# typed: strict
# frozen_string_literal: true

# This policy is used with custom models/fine tuning which won't have any more actors added to it.
# Kept here so that existing users can continue to use the policy without disruption.
# See https://github.slack.com/archives/C06CYDSCSQN/p1755274049351339

module Copilot
  module Policies
    class PrivateTelemetry
      class << self # rubocop:disable Style/ClassMethodsDefinitions
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Instrumentable

        sig { override.returns(String) }
        def config_name
          "private_telemetry"
        end

        sig { override.returns(String) }
        def display_name
          "Telemetry data collection"
        end

        # no docs for this one
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_private_telemetry_access, default: false)
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
        def skip_business_instrumentation?
          true
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
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
            enabled: :PRIVATE_TELEMETRY_ENABLED,
            disabled: :PRIVATE_TELEMETRY_DISABLED,
            no_policy: :PRIVATE_TELEMETRY_DISABLED,
            unconfigured: :PRIVATE_TELEMETRY_UNCONFIGURED,
            unknown: :PRIVATE_TELEMETRY_UNKNOWN
          }
        end
      end
    end
  end
end
