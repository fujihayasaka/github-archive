# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Spark
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Business::Mutable
        include Copilot::Policies::Concerns::Organization::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Organization::Mailable
        include Copilot::Policies::Concerns::User::Cacheable

        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::LeastRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "spark"
        end

        sig { override.returns(String) }
        def display_name
          "Spark"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://gh.io/responsible-use-of-github-spark"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Organizations can have access to",
            PolicyDescriptionChunk.new(text: "GitHub #{display_name}.", href: documentation_url),
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of your enterprise will have access to #{display_name}.",
            PolicyDescriptionChunk.new(text: "Learn more about #{display_name}.", href: documentation_url)
          ]
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          return false unless entity.feature_flag_enabled?(:spark_access_copilot_policy, default: false)

          actor = entity.configurable_object

          policy_enabled = actor.feature_flag_enabled?(:spark_access_copilot_policy, default: false)
          ce_rollout = actor.feature_flag_enabled?(:copilot_ce_rollout, default: false)
          cb_rollout = actor.feature_flag_enabled?(:copilot_cb_rollout, default: false)
          cs_rollout = actor.feature_flag_enabled?(:copilot_cs_rollout, default: false)

          # We can't check the type on entity because it's from BasicObject and lacks is_a?
          # and friends. Instead we check on the actor we retrieved from it.
          copilot_business = actor.is_a?(::Business) ? T.cast(entity, Copilot::Business) : nil

          # For some reason Sorbet is really fussy about this return, assuming it's untyped.
          # It is in fact always a bool, so we cast here to convince it.
          copilot_plan_business = T.cast(entity.copilot_plan_business?, T::Boolean)

          # Fancy type dancing to only look up parent's standalone status on user and org, but not business.
          parent_is_standalone = if !copilot_business
            user_or_org = T.cast(entity, T.any(Copilot::User, Copilot::Organization))
            !!user_or_org.copilot_business&.is_standalone_business?
          else
            false
          end

          business_is_standalone = copilot_business&.is_standalone_business? || parent_is_standalone

          # Allowed if the entity itself says it's enterprise, or if any org in the business
          # has enterprise (even if the business plan reports as non-enterprise).
          is_enterprise =
            copilot_business&.can_access_copilot_enterprise_models? ||
            entity.copilot_plan_enterprise?

          is_business = !business_is_standalone && copilot_plan_business
          is_standalone = business_is_standalone && copilot_plan_business

          ce_enabled = is_enterprise && ce_rollout
          cb_enabled = is_business && cb_rollout
          cs_enabled = is_standalone && cs_rollout

          policy_enabled && (ce_enabled || cb_enabled || cs_enabled)
        end

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          true
        end

        sig { override.returns(T::Boolean) }
        def dpa_covered?
          true
        end

        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          # TODO: uncomment this call when we have fully shipped the spark policy
          # return "disabled" unless available_for?(user)

          # cfi users will always have access
          return "enabled" if user.has_cfi_access?

          # inherited value from org or business
          user_inherited_policy(user, all_policies) || "disabled"
        end

        sig { override.params(copilot_business: Copilot::Business, value: String).void }
        def post_business_update(copilot_business, value)
          if value == "no_policy"
            Copilot::Policies::SparkForceOrg.update_business(copilot_business, value)
          end
        end

        sig { override.params(org: Copilot::Organization).returns(T::Boolean) }
        def skip_email?(org)
          !org.feature_flag_enabled?(:spark_access_policy_emails, default: false)
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_enabled_email(org, user)
          CopilotSparkMailer.spark_enabled_for_user(org, user).deliver_later
        end

        sig { override.params(org: ::Organization, user: ::User).void }
        def send_policy_disabled_email(org, user)
          CopilotSparkMailer.spark_disabled_for_user(org, user).deliver_later
        end

        sig { override.params(copilot_business: Copilot::Business).returns(String) }
        def business_default_value(copilot_business)
          config_values[:disabled]
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(String) }
        def org_default_value(copilot_org)
          config_values[:disabled]
        end

        sig { override.params(copilot_user: Copilot::User).returns(String) }
        def user_default_value(copilot_user)
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
            enabled: :SPARK_ENABLED,
            disabled: :SPARK_DISABLED,
            no_policy: :SPARK_NO_POLICY,
            unconfigured: :SPARK_UNCONFIGURED,
            unknown: :SPARK_UNKNOWN
          }
        end
      end
    end
  end
end
