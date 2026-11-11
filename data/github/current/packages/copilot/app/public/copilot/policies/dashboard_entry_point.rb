# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class DashboardEntryPoint
      class << self # rubocop:disable Style/ClassMethodsDefinitions
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::User::Mutable

        sig { override.returns(String) }
        def config_name
          "dashboard_entry_point"
        end

        sig { override.returns(String) }
        def display_name
          "Dashboard Entry Point"
        end

        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          settings = user.user_object.settings

          settings.get(:copilot_dashboard_entry_point_enabled) ? "enabled" : "disabled"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.is_a?(Copilot::User)
        end

        sig { override.params(copilot_user: Copilot::User, value: String).void }
        def update_user(copilot_user, value)
          return if effective_value(copilot_user) == value
          ActiveRecord::Base.connected_to(role: :writing) do
            copilot_user.user_object.settings.set!(:copilot_dashboard_entry_point_enabled, value == "enabled")
          end

          GitHub.dogstats.increment(
            "copilot.settings.#{config_name}_#{value}",
            tags: ["type:user"],
          )
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def enabled?(entity)
          return false unless available_for?(entity)
          effective_value(T.cast(entity, Copilot::User)) == "enabled"
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def disabled?(entity)
          return false unless available_for?(entity)
          effective_value(T.cast(entity, Copilot::User)) == "disabled"
        end

        # default values
        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          "enabled"
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          "enabled"
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          "enabled"
        end

        sig { override.params(copilot_user: Copilot::User).returns(PolicyDescription) }
        def user_setting_description(copilot_user)
          [
            "Allows instant chatting when landing on GitHub.com"
          ]
        end
      end
    end
  end
end
