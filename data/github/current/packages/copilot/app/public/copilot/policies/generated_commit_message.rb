# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class GeneratedCommitMessage
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "generated_commit_message"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot-generated commit messages"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/en/copilot/responsible-use/copilot-commit-message-generation"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, Copilot will suggest commit messages for changes made on GitHub.com. Learn more about",
            PolicyDescriptionChunk.new(text: display_name, href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, Copilot will suggest commit messages for changes made on GitHub.com.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Allow Copilot to suggest commit messages when you make changes on GitHub.com.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        # intentionally not calling super since we do not want to restrict by CFI access
        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          return false unless viewable_by_user?(copilot_user)

          return true if copilot_user.has_cfi_access?

          # if the inherited value is enabled, user can edit
          inherited_policy = user_inherited_policy(copilot_user)

          return true if inherited_policy == "enabled"

          false
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
          # the value in the users configuration is the effective value if the user has CFI access
          return value_with_default(user) if user.has_cfi_access?

          # inherited value from org or business
          # the inherited value will be one of enabled or disabled (or nil)
          inherited_policy = user_inherited_policy(user, all_policies, skip_ea_fallback: true)

          return inherited_policy if inherited_policy == "disabled"

          # if the inherited value is enabled
          # then the users configuration is the effective value
          return value_with_default(user) if inherited_policy == "enabled"

          ea_fallback_policy = business_copilot_provider_ea_user_fallback_policy(user)

          return ea_fallback_policy if ea_fallback_policy == "disabled"

          # inherited_policy and ea_fallback_policy will be nil if org/business has unconfigured value
          # we should treat unconfigured as disabled for the purposes of this policy
          return "disabled" if ea_fallback_policy.nil? && inherited_policy.nil?

          # If the fallback is enabled or there is no fallback/inherited_policy
          # then the users configuration is the effective value
          value_with_default(user)
        end

        sig { params(user: Copilot::User).returns(String) }
        def value_with_default(user)
          # Exisiting users' configuration won't be defaulted to enabled
          # So if their configuration is unconfigured, we should return enabled to reflect the desired default behavior for users which is enabled
          # New users will have it set by Copilot::Users::Settings#configuration_defaults
          value(user) == "unconfigured" ? "enabled" : value(user)
        end

        sig { override.params(user: Copilot::User).returns(String) }
        def user_default_value(user)
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
            enabled: :GENERATED_COMMIT_MESSAGE_ENABLED,
            disabled: :GENERATED_COMMIT_MESSAGE_DISABLED,
            no_policy: :GENERATED_COMMIT_MESSAGE_NO_POLICY,
            unconfigured: :GENERATED_COMMIT_MESSAGE_UNCONFIGURED,
            unknown: :GENERATED_COMMIT_MESSAGE_UNKNOWN
          }
        end
      end
    end
  end
end
