# typed: strict
# frozen_string_literal: true

module Copilot
  module Policies
    class Memory
      class << self
        include Copilot::PolicyInterface

        include Copilot::Policies::Concerns::Core
        include Copilot::Policies::Concerns::Mutable

        include Copilot::Policies::Concerns::Business::Propagatable
        include Copilot::Policies::Concerns::Instrumentable
        include Copilot::Policies::Concerns::Twirpable

        # INHERITANCE CONFIGURATION:
        # These modules control how policy values are inherited when entities have "unconfigured" settings.
        #
        # BusinessPrecedence: When both business and org have configured values, business wins.
        #   - This allows businesses to override org settings for centralized control.
        #   - To change: Replace with `Copilot::Policies::Inheritance::OrgPrecedence` to let orgs override business.
        #
        # MostRestrictiveBusiness: When multiple orgs exist, take the most restrictive (locked-down) setting.
        #   - This is safer for security/privacy features like Memory.
        #   - To change: Replace with `Copilot::Policies::Inheritance::LeastRestrictiveBusiness` for more permissive behavior.
        #
        # LeastRestrictiveOrg: When org is unconfigured, inherit from business in a permissive way.
        #   - If business says "enabled", users get "enabled". If business says "disabled", users get "disabled".
        #   - When business is "unconfigured" or "no_policy", orgs can opt in independently.
        #   - To change: Replace with `Copilot::Policies::Inheritance::MostRestrictiveOrg` to always default to disabled.
        include Copilot::Policies::Inheritance::BusinessPrecedence
        include Copilot::Policies::Inheritance::MostRestrictiveBusiness
        include Copilot::Policies::Inheritance::LeastRestrictiveOrg

        sig { override.returns(String) }
        def config_name
          "memory" # matches the enum in configuration.rb
        end

        ### BEGIN UI
        sig { override.returns(String) }
        def display_name
          "Copilot Memory"
        end

        sig { override.returns(String) }
        def documentation_url
          "https://docs.github.com/copilot/concepts/agents/copilot-memory"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          [
            "Organizations can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: documentation_url),
            "to remember repository context across Copilot agent interactions."
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          [
            "If enabled, members of this organization can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: documentation_url),
            "to remember repository context across Copilot agent interactions."
          ]
        end

        sig { returns(String) }
        def organization_setting_payload_description
          "If enabled, members of this organization can use Copilot Memory to remember repository context across Copilot agent interactions."
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          [
            "You can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: documentation_url),
            "to remember repository context across Copilot agent interactions."
          ]
        end

        # EDITABLE BEHAVIOR: Controls when users can configure Memory individually vs. inherit from org/business.
        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          # Check if org policy should take precedence
          org_precedence_enabled = copilot_user.feature_flag_enabled?(:copilot_memory_enablement_policy_with_orgs, default: false)

          # Phase 1 (flag OFF - shipping first): Only Pro/Pro+/Max users can edit individually
          unless org_precedence_enabled
            return copilot_user.copilot_plan_at_least?(min_cfi_plan: Copilot::Plans::CFI::Pro, min_cfb_plan: nil) || copilot_user.user_object.employee?
          end

          # Phase 2 (flag ON - shipping later): Only users Pro/Pro+/Max NOT in an org, standalone business, or enterprise team can edit
          # - Pro/Pro+/Max in orgs: inherit from org (cannot edit)
          # - CFB/CFE in orgs: inherit from org (cannot edit)
          # - CFB/CFE in standalone business: inherit from business (cannot edit)
          # - CFB/CFE via enterprise team (no org): inherit from business (cannot edit)
          # - Pro/Pro+/Max NOT in orgs or businesses: can edit individually
          (copilot_user.copilot_organizations.empty? && copilot_user.copilot_standalone_businesses.to_a.empty? && copilot_user.copilot_businesses.empty?) &&
            copilot_user.copilot_plan_at_least?(min_cfi_plan: Copilot::Plans::CFI::Pro, min_cfb_plan: nil) || false
        end

        ### END UI

        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def available_for?(entity)
          # Gate the entire policy behind the enablement feature flag
          return false unless entity.feature_flag_enabled?(:copilot_memory_enablement_policy, default: false)

          # Phase 1 (shipping first): When org precedence is NOT yet enabled, only individual Pro/Pro+/Max users can see it
          unless entity.feature_flag_enabled?(:copilot_memory_enablement_policy_with_orgs, default: false)
            # Only available for individual Pro/Pro+/Max users
            if entity.sorbet_class == ::User
              copilot_user = T.cast(entity, Copilot::User)

              # Allow GitHub employees to access the policy individually in Phase 1.
              # In Phase 2 (org precedence enabled), they will inherit from their org/business policy instead.
              return true if copilot_user.user_object.employee?

              # Exclude Limited access
              return false if copilot_user.has_limited_access?

              # Exclude Free users
              return false if copilot_user.has_free_access?

              # - Pro, Pro+, MAX individual users
              return copilot_user.copilot_plan_at_least?(min_cfi_plan: Copilot::Plans::CFI::Pro, min_cfb_plan: nil)
            else
              # Orgs/Businesses cannot see it yet in Phase 1
              return false
            end
          end

          # Phase 2 (shipping later): When org precedence is enabled, expand to orgs/businesses
          # Available for:
          # - CFB Business and Enterprise organizations
          # - CFI Pro, Pro+, Max individual users
          # NOT available for Free/Limited users
          copilot_plan_at_least?(entity, min_cfb_plan: Copilot::Plans::CFB::Business, min_cfi_plan: Copilot::Plans::CFI::Pro)
        end

        sig { override.params(copilot_org: Copilot::Organization).returns(T::Boolean) }
        def viewable_by_org?(copilot_org)
          copilot_org.feature_flag_enabled?(:copilot_memory_enablement_policy_with_orgs, default: false) && available_for?(copilot_org)
        end

        # PREVIEW BADGE CONFIGURATION:
        # Shows "preview" badge when the GA feature flag is NOT enabled.
        # The feature flag is: copilot_memory_enablement_policy_ga
        # To change: Modify the feature flag name or return false to never show preview badge.
        sig { override.params(entity: Copilot::Types::CopilotEntity).returns(T::Boolean) }
        def preview?(entity)
          !entity.feature_flag_enabled?(:copilot_memory_enablement_policy_ga, default: false)
        end

        ## TODO: Is this needed for copilot memory? It is on Copilot CLI, Insights, Loops, and Spark.
        ## If so, true, the business policies will include a DPA coverage notice.
        sig { override.returns(T::Boolean) }
        def dpa_covered?
          false
        end

        # EFFECTIVE VALUE LOGIC:
        # This method determines the final policy value for a user, considering inheritance.
        #
        # SPECIAL BEHAVIOR for Memory policy:
        # 1. Pro/Pro+/Max users can configure individually (current behavior with flag disabled)
        #    - If unconfigured and copilot_memory_enablement_policy_user_default_enabled flag is ON, defaults to "enabled" (opt-out)
        #    - If unconfigured and copilot_memory_enablement_policy_user_default_enabled flag is OFF, remains "unconfigured"
        # 2. FUTURE: When copilot_memory_enablement_policy_with_orgs flag is enabled:
        #    - Org/business policy overrides Pro/Pro+/Max settings
        #    - If org/business is unconfigured, treat as "disabled" (Pro users cannot enable)
        #    - Pro users must wait for their org to enable Memory
        # 3. Businesses that are "unconfigured" behave as "no_policy" (orgs can opt in without business configuration)
        # 4. Business/Enterprise users always inherit from org/business
        # 5. Standalone business users inherit from their business setting
        # 6. Users NOT in any org/business default to "enabled" when unconfigured (if copilot_memory_enablement_policy_user_default_enabled flag is ON)
        #
        # To enable org precedence for Pro/Pro+/Max users, enable the copilot_memory_enablement_policy_with_orgs feature flag.
        sig { override.params(user: Copilot::User, all_policies: T.nilable(Copilot::Users::Policies::CopilotAllPolicies)).returns(String) }
        def effective_value(user, all_policies = nil)
          return "disabled" unless available_for?(user)

          # Check if org policy should take precedence over individual Pro/Pro+/Max settings
          org_precedence_enabled = user.feature_flag_enabled?(:copilot_memory_enablement_policy_with_orgs, default: false)

          # Pro/Pro+/Max users can always configure individually when org precedence is disabled.
          # GitHub employees are treated like Pro users in Phase 1 (auto-enabled when default flag is on).
          # In Phase 2 (org precedence enabled), employees will inherit from their org/business policy instead.
          # If their value is "unconfigured" and the enabled-by-default flag is on, default to "enabled".
          if (user.copilot_plan_at_least?(min_cfi_plan: Copilot::Plans::CFI::Pro, min_cfb_plan: nil) || user.user_object.employee?) && !org_precedence_enabled
            user_value = value(user)
            return resolve_unconfigured_default(user, user_value)
          end

          # If user is in an organization or business (including via enterprise teams), use org/business policy
          # (This applies to: Business/Enterprise users always, and Pro/Pro+/Max when org_precedence is enabled)
          #
          # Note: copilot_organizations and copilot_standalone_businesses are checked first (with short-circuit)
          # to avoid calling copilot_businesses for users already covered. copilot_businesses involves an additional
          # async_seats query, so it is only reached for enterprise-team users who have no org or standalone business.
          has_org_or_business = user.copilot_organizations.any? || user.copilot_standalone_businesses&.any? ||
            user.copilot_businesses.any?

          if has_org_or_business
            # inherited value from org or business
            inherited_policy = user_inherited_policy(user, all_policies)

            resolution_path = if user.copilot_organizations.any?
              "org"
            elsif user.copilot_standalone_businesses&.any?
              "standalone_business"
            else
              "enterprise_team"
            end

            GitHub.dogstats.increment(
              "copilot.policies.memory.effective_value",
              tags: [
                "resolution_path:inherited",
                "source:#{resolution_path}",
                "result:#{inherited_policy || 'disabled'}",
              ],
            )

            # If org/business is unconfigured, treat as disabled
            # This means Pro/Pro+/Max users in orgs must wait for their org to enable Memory
            inherited_policy || "disabled"
          else
            # User is NOT in an org or business, they can configure individually.
            # If their value is "unconfigured" and the enabled-by-default flag is on, default to "enabled".
            user_value = value(user)
            resolved = resolve_unconfigured_default(user, user_value)

            GitHub.dogstats.increment(
              "copilot.policies.memory.effective_value",
              tags: [
                "resolution_path:individual",
                "source:none",
                "result:#{resolved}",
              ],
            )

            resolved
          end
        end

        private

        # Resolves "unconfigured" to "enabled" when the copilot_memory_enablement_policy_user_default_enabled flag is on.
        # This provides an opt-out experience for individual Pro/Pro+/Max users.
        sig { params(user: Copilot::User, user_value: String).returns(String) }
        def resolve_unconfigured_default(user, user_value)
          if user_value == "unconfigured" && user.feature_flag_enabled?(:copilot_memory_enablement_policy_user_default_enabled, default: false)
            "enabled"
          else
            user_value
          end
        end

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
            enabled: :MEMORY_ENABLED,
            disabled: :MEMORY_DISABLED,
            no_policy: :MEMORY_NO_POLICY,
            unconfigured: :MEMORY_UNCONFIGURED,
            unknown: :MEMORY_UNKNOWN
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
            enabled: MonolithTwirp::Copilot::Users::V1::Memory::MEMORY_ENABLED,
            disabled: MonolithTwirp::Copilot::Users::V1::Memory::MEMORY_DISABLED,
            no_policy: MonolithTwirp::Copilot::Users::V1::Memory::MEMORY_DISABLED, # no_policy is invalid for users, so we assume disabled
            unconfigured: MonolithTwirp::Copilot::Users::V1::Memory::MEMORY_UNCONFIGURED,
            invalid: MonolithTwirp::Copilot::Users::V1::Memory::MEMORY_INVALID
          }
        end
      end
    end
  end
end
