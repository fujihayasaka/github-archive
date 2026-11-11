# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class CodingAgent
      class << self
        include Copilot::Policy

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable
        include Copilot::Policies::Concerns::Organization::Mailable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "swe_agent"
        end

        sig { override.returns(String) }
        def display_name
          "Copilot coding agent"
        end

        # multiple docs links
        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/assigncopilot"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "If enabled, users assigned a Copilot license from this enterprise will have access to #{display_name} in repositories where it is enabled. This feature may use models which are not enabled on your \"Models\" settings page.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, users assigned a Copilot license from this organization will have access to #{display_name} in repositories where it is enabled. This feature may use models which are not enabled on your Models settings page.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "Delegate tasks to #{display_name} in repositories where it is enabled.",
            PolicyDescriptionChunk.new(text: "Learn more.", href: documentation_url)
          ]
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def viewable_by_user?(copilot_user)
          return false unless super

          if copilot_user.has_cfi_access?
            return true unless copilot_user.has_limited_access?
          end

          #check org for flag and plans
          return true if copilot_user.copilot_organizations_including_trials.any? do |cp_org|
            enterprise_enabled = cp_org.copilot_plan_enterprise? || cp_org.on_free_copilot_enterprise_trial?
            business_enabled = cp_org.copilot_plan_business? || cp_org.on_free_copilot_business_trial?

            cp_org.copilot_enabled? && (enterprise_enabled || business_enabled)
          end

          #check business (if any) for flag and plans
          return true if copilot_user.copilot_businesses_including_trials.any? do |business|
            enterprise_enabled = business.copilot_plan_enterprise? || business.on_free_copilot_enterprise_trial?
            business_enabled = business.copilot_plan_business? || business.business_object.trial?

            business.copilot_enabled? && (enterprise_enabled || business_enabled)
          end

          false
        end

        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          false
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          experimental_copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro) do
            if entity.sorbet_class == ::User
              user = T.cast(entity, Copilot::User)
              return false if user.has_limited_access?
            end

            # non standalone businesses and orgs should have access, regardless of access/trial
            # also any user either paying/trial or a part of cfe/cfb biz/org should have access as well
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

          # paying/trial cfi users will always have access
          return "enabled" if user.has_cfi_access? || user.has_trial_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "unconfigured"
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotSweAgentMailer.swe_agent_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotSweAgentMailer.swe_agent_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          !GitHub.multi_tenant_enterprise? || copilot_org.feature_flag_enabled?(:coding_agent_in_proxima, default: false)
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
            enabled: :SWE_AGENT_ENABLED,
            disabled: :SWE_AGENT_DISABLED,
            no_policy: :SWE_AGENT_NO_POLICY,
            unconfigured: :SWE_AGENT_UNCONFIGURED,
            unknown: :SWE_AGENT_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_DISABLED,
            unconfigured: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::SWEAgent::SWE_AGENT_INVALID
          }
        end
      end
    end
  end
end
