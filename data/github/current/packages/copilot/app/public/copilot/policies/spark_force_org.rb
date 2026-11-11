# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class SparkForceOrg
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::MostRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "spark_force_org"
        end

        sig { override.returns(String) }
        def display_name
          "Spark force repository creation to organization"
        end

        # no docs for this one
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["When a user creates a repository from their Spark, force it to be in the organization instead of the user account."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["When a user creates a repository from their Spark, force it to be in the organization instead of the user account."]
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
          # cfi users will always have access
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "disabled"
        end

        sig { override.returns(T::Boolean) }
        def skip_user_instrumentation?
          true
        end

        sig { override.params(business: Copilot::Business).returns(String) }
        def business_default_value(business)
          config_values[:disabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:disabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:disabled]
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
            enabled: :SPARK_FORCE_ORG_ENABLED,
            disabled: :SPARK_FORCE_ORG_DISABLED,
            no_policy: :SPARK_FORCE_ORG_NO_POLICY,
            unconfigured: :SPARK_FORCE_ORG_UNCONFIGURED,
            unknown: :SPARK_FORCE_ORG_UNKNOWN
          }
        end
      end
    end
  end
end
