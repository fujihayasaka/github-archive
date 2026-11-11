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

        # The default URL (and method) used for the trailing link in React based policies (organizations)
        sig { override.returns(String) }
        def documentation_url
          memory_documentation_url
        end

        sig { returns(String) }
        def memory_documentation_url
          "https://docs.github.com/copilot/concepts/agents/copilot-memory"
        end

        sig { returns(String) }
        def privacy_statement_url
          "https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement"
        end

        sig { override.params(business: Copilot::Business).returns(Copilot::Policies::PolicyDescription) }
        def business_setting_description(business)
          user_scoped_memories = business.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false)

          scope = policy_description_scope(user_scoped_memories: user_scoped_memories)

          [
            "Members can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: memory_documentation_url),
            "to store #{scope}.",
            "These are available to agents in future sessions. Users can turn this off at any time, regardless of enterprise or organization policy.",
            "Learn more in the",
            PolicyDescriptionChunk.new(text: "Privacy Statement.", href: privacy_statement_url),
          ]
        end

        sig { override.params(org: Copilot::Organization).returns(Copilot::Policies::PolicyDescription) }
        def organization_setting_description(org)
          user_scoped_memories = org.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false)

          scope = policy_description_scope(user_scoped_memories: user_scoped_memories)

          [
            "Members can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: memory_documentation_url),
            "to store #{scope}.",
            "These are available to agents in future sessions. Users can turn this off at any time, regardless of enterprise or organization policy.",
            "Learn more in the",
            PolicyDescriptionChunk.new(text: "Privacy Statement.", href: privacy_statement_url),
          ]
        end

        sig { params(user_scoped_memories: T::Boolean).returns(String) }
        def organization_setting_payload_description(user_scoped_memories: false)
          scope = policy_description_scope(user_scoped_memories: user_scoped_memories)

          "Members can use Copilot Memory to store #{scope}. These are available to agents in future sessions. Users can turn this off at any time, regardless of enterprise or organization policy."
        end

        sig { params(user_scoped_memories: T::Boolean, for_user_policy_description: T::Boolean).returns(String) }
        def policy_description_scope(user_scoped_memories:, for_user_policy_description: false)
          return "facts about repositories" unless user_scoped_memories

          pronoun = for_user_policy_description ? "you" : "they"
          "facts about repositories and personal preferences about how #{pronoun} want to interact with Copilot"
        end

        sig { override.params(user: Copilot::User).returns(Copilot::Policies::PolicyDescription) }
        def user_setting_description(user)
          user_scoped_memories = user_scoped_memory_available_for?(user)

          scope = policy_description_scope(
            user_scoped_memories: user_scoped_memories,
            for_user_policy_description: true
          )

          [
            "You can use",
            PolicyDescriptionChunk.new(text: "Copilot Memory", href: memory_documentation_url),
            "to store #{scope}.",
            "These are available to agents in future sessions. You can turn this off at any time, regardless of enterprise or organization policy.",
            "Learn more in the",
            PolicyDescriptionChunk.new(text: "Privacy Statement.", href: privacy_statement_url),
          ]
        end

        # USER-SCOPED MEMORY AVAILABILITY:
        # Determines whether the user-scoped memory variant (vs. repo-scoped only) is available
        # to a given user. The two rollout flags are independent and gate different audiences:
        #
        # - CFI Pro/Pro+/Max individual users: gated solely by `copilot_feature_agentic_memory_user_scoped_cfi`.
        # - Everyone else (CFB, employees, etc.): gated solely by `copilot_feature_agentic_memory_user_scoped`.
        sig { params(copilot_user: Copilot::User).returns(T::Boolean) }
        def user_scoped_memory_available_for?(copilot_user)
          if copilot_user.copilot_plan_at_least?(min_cfi_plan: Copilot::Plans::CFI::Pro, min_cfb_plan: nil)
            copilot_user.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped_cfi, default: false)
          else
            copilot_user.feature_flag_enabled?(:copilot_feature_agentic_memory_user_scoped, default: false)
          end
        end

        # EDITABLE BEHAVIOR: Controls when users can configure Memory individually.
        #
        # When the `copilot_user_scoped_memories_policy_opt_out` feature flag is ENABLED (new behavior):
        #   Memory is opt-out at the user level: even when an org/business has enabled Memory,
        #   individual users must be able to disable it for themselves. The org/business setting
        #   acts as a ceiling (org "disabled" cannot be overridden up to "enabled"), but users
        #   can always toggle their own value down to "disabled". Any user the policy is
        #   available for can edit their own setting.
        #
        # When the `copilot_user_scoped_memories_policy_opt_out` feature flag is DISABLED (old behavior):
        #   - Phase 1 (org precedence flag OFF): Only Pro/Pro+/Max users (and employees) can edit individually.
        #   - Phase 2 (org precedence flag ON): Only Pro/Pro+/Max users NOT in an org, standalone
        #     business, or enterprise team can edit. Everyone else inherits from org/business.
        sig { override.params(copilot_user: Copilot::User).returns(T::Boolean) }
        def editable_by_user?(copilot_user)
          memory_is_enabled = copilot_user.feature_flag_enabled?(:copilot_memory_enablement_policy, default: false)
          user_is_covered_by_org_or_business = !copilot_user.copilot_plan_individual?
          user_policy_opt_out_enabled = copilot_user.feature_flag_enabled?(:copilot_user_scoped_memories_policy_opt_out, default: false)
          user_inherits_memory_from_entity = copilot_user.feature_flag_enabled?(:copilot_memory_enablement_policy_with_orgs, default: false)

          return false if !memory_is_enabled

          # Covered users
          if user_is_covered_by_org_or_business
            if !user_inherits_memory_from_entity
              return available_for?(copilot_user)
            end

            # org controls memory
            if user_policy_opt_out_enabled
              return user_inherited_policy(copilot_user) == "enabled"
            end
            return false
          end

          # Individual users
          available_for?(copilot_user) # practically user_is_at_least_pro || copilot_user.user_object.employee?
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
        # Determines the final Memory policy value for a user.
        # Memory covers BOTH user-scoped and repo-scoped memories under a single setting.
        # Disabling Memory does NOT delete existing memories.
        #
        # Feature flags:
        #   - copilot_memory_enablement_policy_with_orgs ("org precedence"):
        #       OFF (Phase 1) — Pro/Pro+/Max and employees configure Memory individually.
        #       ON  (Phase 2) — users in an org / standalone business / enterprise team
        #                       inherit from org/business policy.
        #   - copilot_memory_enablement_policy_user_default_enabled ("default-enabled"):
        #       ON — a user's "unconfigured" value resolves to "enabled" (opt-out UX).
        #            Only applies on the individual-resolution path (not inherited from org/business).
        #   - copilot_user_scoped_memories_policy_opt_out ("user opt-out"):
        #       Gates editability only (see `editable_by_user?`). Resolution here always
        #       honors a stored user value of "disabled" as an opt-out when org/business
        #       is "enabled"; this flag controls whether users can SET that "disabled"
        #       value when they're covered by an org/business policy.
        #
        # Decision tree (mirrors the method below):
        #   1. If not available_for?(user)              -> "disabled"
        #
        #   2. Phase 1 short-circuit:
        #      org-precedence is OFF AND user is Pro/Pro+/Max or employee
        #        -> user's own value
        #           ("unconfigured" -> "enabled" if default-enabled flag is ON)
        #
        #   3. Otherwise, branch on whether the user belongs to an org, standalone
        #      business, or enterprise team:
        #
        #      a. In an org/business (inherited path):
        #           inherited = org/business policy value
        #           if inherited == "enabled" AND user value == "disabled" -> "disabled"
        #             (opt-out is honored regardless of the user-opt-out flag — that flag
        #              only gates writes via `editable_by_user?`. Reads always respect a
        #              stored "disabled" so users who opted out stay opted out if the flag
        #              is later turned off.)
        #           else -> inherited or "disabled" (ceiling)
        #
        #      b. Not in any org/business (individual path):
        #           -> user's own value
        #              ("unconfigured" -> "enabled" if default-enabled flag is ON)
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

            # User-level opt-out: when the org/business has enabled Memory, the user can still
            # individually disable it for themselves by setting their own value to "disabled".
            # The org/business setting acts as a ceiling, not an absolute override.
            user_opted_out = inherited_policy == "enabled" && value(user) == "disabled"
            resolved = if user_opted_out
              "disabled"
            else
              # If org/business is unconfigured, treat as disabled
              # This means Pro/Pro+/Max users in orgs must wait for their org to enable Memory
              inherited_policy || "disabled"
            end

            GitHub.dogstats.increment(
              "copilot.policies.memory.effective_value",
              tags: [
                "resolution_path:inherited",
                "source:#{resolution_path}",
                "result:#{resolved}",
                "user_opted_out:#{user_opted_out}",
              ],
            )

            resolved
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

        # Override update_user to capture the old value before the write, so we
        # can detect an actual opt-out transition (non-disabled -> disabled).
        # Gated behind the copilot_memory_opt_out_audit_log feature flag.
        sig { override.params(copilot_user: Copilot::User, value: String).void }
        def update_user(copilot_user, value)
          old_value = self.value(copilot_user)
          super(copilot_user, value)

          # Only emit audit log on actual transition TO disabled
          if value == "disabled" && old_value != "disabled"
            if copilot_user.feature_flag_enabled?(:copilot_memory_opt_out_audit_log, default: false)
              Copilot::Instrumenter.instrument_memory_user_opt_out(copilot_user)
            end
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
