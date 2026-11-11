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
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

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

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          []
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          []
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          false
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_private_telemetry_access, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # this policy reads directly from the configuration
          value(user)
        end
      end
    end
  end
end
