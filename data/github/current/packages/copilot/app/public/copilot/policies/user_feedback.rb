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
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
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

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          true
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          false
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(T.nilable(String)) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          inherited_policy = user_inherited_policy(user, all_policies)

          # the inherited value will be one of enabled or disabled (or nil)
          # if inherited value is nil, that means the policy is not configured
          # so we default to disabled
          inherited_policy || "disabled"
        end

        sig { override.params(business: Copilot::Business, org: Copilot::Organization).returns(T::Boolean) }
        def propagate_business_updates?(business, org)
          true
        end

        sig { override.returns(Symbol) }
        def instrumentation_key
          :copilot_user_feedback_opt_in_setting
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
            enabled: :COPILOT_USER_FEEDBACK_OPT_IN_ENABLED,
            disabled: :COPILOT_USER_FEEDBACK_OPT_IN_DISABLED,
            no_policy: :COPILOT_USER_FEEDBACK_OPT_IN_DISABLED,
            unconfigured: :COPILOT_USER_FEEDBACK_OPT_IN_DISABLED,
            unknown: :COPILOT_USER_FEEDBACK_OPT_IN_UNKNOWN
          }
        end
      end
    end
  end
end
