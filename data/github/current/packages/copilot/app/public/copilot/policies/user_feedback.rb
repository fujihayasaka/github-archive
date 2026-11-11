# typed: strict
# frozen_string_literal: true

# TODO: when writing logic to update this policy, we should be sure that changes to dotcom chat
# update this policy. if dotcom chat is no policy, so is this policy, if dotcom chat is enabled, this policy
# should be set to disabled (only if the policy is no policy)
# if disabling dotcom chat, disable this policy

module Copilot
  module Policies
    class UserFeedback
      class << self # rubocop:disable Style/ClassMethodsDefinitions
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::MostRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "user_feedback_opt_in"
        end

        sig { override.returns(String) }
        def display_name
          "User feedback collection"
        end

        # no docs for this one
        sig { override.returns(String) }
        def documentation_url
          ""
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          ["Enables user feedback collection on Copilot features in github.com. This feedback may include sensitive information."]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          ["Enables user feedback collection on Copilot features in github.com. This feedback may include sensitive information."]
        end

        sig { override.params(copilot_business: Copilot::Business).returns(T::Boolean) }
        def viewable_by_business?(copilot_business)
          super && Dotcom.enabled?(copilot_business)
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
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "disabled"
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:enabled]
        end

        sig { override.params(org: Copilot::Organization).returns(String) }
        def org_default_value(org)
          config_values[:enabled]
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
          config_values[:disabled]
        end
      end
    end
  end
end
