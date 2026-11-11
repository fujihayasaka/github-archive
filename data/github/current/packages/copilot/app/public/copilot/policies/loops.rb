# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Loops
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Organization::Mailable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "loops"
        end

        sig { override.returns(String) }
        def display_name
          "Loops"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/copilot/concepts/loops"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Members with a Copilot license can access",
            PolicyDescriptionChunk.new(text: display_name, href: documentation_url),
            ". Note that users can make any loop they create publicly visible."
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of your organization will have access to #{display_name}.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "If enabled, you will have access to #{display_name}, GitHub's collaborative AI-powered workspace for ideation and iteration.",
            PolicyDescriptionChunk.new(text: "Learn more", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          entity.feature_flag_enabled?(:copilot_loops_access_copilot_policy, default: false)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          !entity.feature_flag_enabled?(:copilot_loops_ga, default: false)
        end

        sig { override.returns(T::Boolean) }
        def dpa_covered?
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_email?(org)
          !org.feature_flag_enabled?(:copilot_loops_access_policy_emails, default: false)
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          # TODO: Create CopilotLoopsMailer when needed
          # CopilotLoopsMailer.loops_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          # TODO: Create CopilotLoopsMailer when needed
          # CopilotLoopsMailer.loops_disabled_for_user(org, user).deliver_later
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
            enabled: :LOOPS_ENABLED,
            disabled: :LOOPS_DISABLED,
            no_policy: :LOOPS_NO_POLICY,
            unconfigured: :LOOPS_UNCONFIGURED,
            unknown: :LOOPS_UNKNOWN
          }
        end
      end
    end
  end
end
