# typed: strict
# frozen_string_literal: true

# This policy is only modified by the "Copilot for Dotcom"
# setting, we should consider removing this class in favor of
# a pseudo policy that groups policies like these

module Copilot
  module Policies
    class PrSummarizations
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "pr_summarizations"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot for pull requests"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/enterprise-cloud@latest/copilot/github-copilot-enterprise/copilot-pull-request-summaries/creating-a-pull-request-summary-with-github-copilot"
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

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro) do
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return false if user.has_limited_access?
            end

            true
          end
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.returns(Symbol) }
        def twirp_key
          :pr_summarization
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:enabled]
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
            enabled: :PR_SUMMARIZATIONS_ENABLED,
            disabled: :PR_SUMMARIZATIONS_DISABLED,
            no_policy: :PR_SUMMARIZATIONS_NO_POLICY,
            unconfigured: :PR_SUMMARIZATIONS_UNCONFIGURED,
            unknown: :PR_SUMMARIZATIONS_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_NO_POLICY,
            unconfigured: MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::PRSummarization::PR_SUMMARIZATION_INVALID
          }
        end
      end
    end
  end
end
