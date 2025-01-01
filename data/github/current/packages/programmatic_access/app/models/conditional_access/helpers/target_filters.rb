# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Helpers
    module TargetFilters
      BATCH_SIZE = 1_000
      ActorOrganizationsAndBusinessMemberships = Struct.new(:organization_ids, :direct_organization_ids, :business_memberships)

      private

      # Internal: Is the target applicable to the policy?
      #
      # Returns a Boolean.
      def target_applicable?(target)
        return false if target == :no_target_for_conditional_access
        target.instance_of?(Organization) || target.instance_of?(Business)
      end

      def organization_ids_restricting_pat_access_candidate(configuration_key:, targets:)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit::AppliedIn
        ))

        policy_debug_logging("Checking for organizations restricting PAT access", "organization_ids_restricting_pat_access_candidate", {
          "gh.configuration_key" => configuration_key,
        })

        return [] if targets.empty?

        # Get IDs of orgs restricting PAT access directly at the org level.
        org_and_memberships = actor_organization_ids_and_business_memberships_candidate(actor, targets)

        if GitHub.single_business_environment? && GitHub.global_business.present?
          if business_ids_with_configuration_enabled([GitHub.global_business.id], configuration_key).any?
            return org_and_memberships.organization_ids
          end
        end

        restricted_org_ids = organization_ids_with_configuration_enabled(org_and_memberships.direct_organization_ids, configuration_key)

        return [] if restricted_org_ids.empty? && org_and_memberships.business_memberships.empty?

        business_memberships = org_and_memberships.business_memberships
        return restricted_org_ids if business_memberships.empty?

        # Get IDs of businesses that restrict access on orgs.
        membership_business_ids = business_memberships.map(&:business_id).uniq
        restricted_business_ids = business_ids_with_configuration_enabled(membership_business_ids, configuration_key)

        return [] if restricted_org_ids.empty? && restricted_business_ids.empty?

        # Only keep memberships where the org is restricted by the business.
        restricted_business_memberships = business_memberships.filter { |membership| restricted_business_ids.include?(membership.business_id) }

        (restricted_business_memberships.map(&:organization_id) | restricted_org_ids).compact
      end

      def organization_ids_restricting_pat_access(configuration_key:)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit::AppliedIn
        ))

        # Get IDs of orgs restricting PAT access directly at the org level.
        org_and_memberships = actor_organization_ids_and_business_memberships(actor)
        org_ids = organization_ids_with_configuration_enabled(org_and_memberships.direct_organization_ids, configuration_key)

        return [] if org_ids.empty? && org_and_memberships.business_memberships.empty?

        business_memberships = org_and_memberships.business_memberships
        if business_memberships.any?
          # Get IDs of businesses that restrict access on orgs.
          business_ids = business_memberships.map(&:business_id).uniq
          business_ids = business_ids_with_configuration_enabled(business_ids, configuration_key)

          return [] if org_ids.empty? && business_ids.empty?

          # Only keep memberships where the org is restricted by the business.
          business_memberships = business_memberships.filter { |membership| business_ids.include?(membership.business_id) }

          # And only keep org_ids where orgs are restricted directly, without
          # an owning protecting business entry.
          org_ids = org_ids.difference(business_memberships.map(&:organization_id))

          return [] if org_ids.empty? && business_memberships.empty?
        end

        (business_memberships.map(&:organization_id) + org_ids).uniq.compact
      end

      # Internal: Find all of the actor's associated Businesses IDs that enforce an expiration policy the PAT doesn't adhere to.
      #
      # Returns an Array.
      def business_ids_restricting_pat_lifetime(pat_lifetime, pat_type)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit::AppliedIn
        ))

        # All business IDs the actor is a member of.
        business_ids = actor.business_ids

        # Businesses IDs the actor administrates and exempt administrators.
        business_ids_exempting_actor = business_ids_with_pat_lifetime_limit_exemptions(pat_type: pat_type)

        # Only keep business_ids where the actor is not exempted from the limit.
        business_ids.keep_if { |business_id| business_ids_exempting_actor.exclude?(business_id) }

        business_ids_with_pat_lifetime_restricted_by_limit(business_ids: business_ids, lifetime_limit: expirable_access.pat_lifetime_in_days, pat_type: expirable_access.pat_type)
      end

      def organization_ids_restricting_pat_lifetime_candidate(pat_lifetime, pat_type, targets: [])
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn
        ))
        return [] if targets.empty?

        org_and_memberships = actor_organization_ids_and_business_memberships_candidate(actor, targets)
        return [] if org_and_memberships.organization_ids.empty?

        # Businesses the actor administrates and exempt administrators. We look this up early for the single_business_environment case.
        business_ids_exempting_actor = business_ids_with_pat_lifetime_limit_exemptions(pat_type: pat_type)

        if GitHub.single_business_environment? && GitHub.global_business.present?
          # If the global business is exempted, we don't need to check its PAT lifetime limit.
          return [] if business_ids_exempting_actor.include?(GitHub.global_business.id)

          if business_ids_with_pat_lifetime_restricted_by_limit(
              business_ids: [GitHub.global_business.id],
              lifetime_limit: pat_lifetime,
              pat_type: pat_type
          ).any?
            return org_and_memberships.organization_ids
          end
        end

        # Get IDs of orgs restricting PAT access directly at the org level.
        restricted_org_ids = organization_ids_with_pat_lifetime_restricted_by_limit(organization_ids: org_and_memberships.direct_organization_ids, lifetime_limit: pat_lifetime, pat_type: pat_type)
        # They're not restricted directly by an org and they're not part of a business-owned org.
        if restricted_org_ids.empty? && org_and_memberships.business_memberships.empty?
          return []
        end

        business_memberships = org_and_memberships.business_memberships
        return restricted_org_ids if business_memberships.empty?

        # Get IDs of businesses that restrict access on orgs.
        membership_business_ids = business_memberships.map(&:business_id).uniq
        restricted_business_ids = business_ids_with_pat_lifetime_restricted_by_limit(business_ids: membership_business_ids, lifetime_limit: pat_lifetime, pat_type: pat_type)

        if restricted_org_ids.empty? && restricted_business_ids.empty?
          return []
        end

        # Only keep memberships where the org is restricted by the business.
        restricted_business_memberships = business_memberships.filter { |membership| restricted_business_ids.include?(membership.business_id) }

        # Only keep memberships where the actor is not exempted from the limit.
        non_exempt_restricted_business_memberships = restricted_business_memberships.filter { |membership| business_ids_exempting_actor.exclude?(membership.business_id) }

        # And only keep restricted_org_ids where orgs are restricted directly, without
        # an owning protecting business entry.
        (non_exempt_restricted_business_memberships.map(&:organization_id) | restricted_org_ids).compact
      end

      # method to filter organization ids restricting PAT lifetime combined with the limit
      # of businesses as well
      #
      def organization_ids_restricting_pat_lifetime(pat_lifetime, pat_type)
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn,
        ))

        policy_debug_logging("Checking for organizations restricting PAT lifetime", "organization_ids_restricting_pat_lifetime", {
          "gh.pat_lifetime.value" => pat_lifetime,
          "gh.pat_type.value" => pat_type,
        })
        org_and_memberships = actor_organization_ids_and_business_memberships(actor)
        policy_debug_logging("org_and_memberships from actor_organization_ids_and_business_memberships", "organization_ids_restricting_pat_lifetime", {
          "gh.org_and_memberships.organization_ids" => org_and_memberships.organization_ids,
          "gh.org_and_memberships.direct_organization_ids" => org_and_memberships.direct_organization_ids,
          "gh.org_and_memberships.business_memberships" => org_and_memberships.business_memberships,
        })
        return [] if org_and_memberships.organization_ids.empty?

        # Get IDs of orgs restricting PAT access directly at the org level.
        org_ids = organization_ids_with_pat_lifetime_restricted_by_limit(organization_ids: org_and_memberships.organization_ids, lifetime_limit: pat_lifetime, pat_type: pat_type)
        policy_debug_logging("org_ids from organization_ids_with_pat_lifetime_restricted_by_limit", "organization_ids_restricting_pat_lifetime", {
          "gh.org_ids" => org_ids,
        })
        # They're not restricted directly by an org and they're not part of a business-owned org.
        if org_ids.empty? && org_and_memberships.business_memberships.empty?
          policy_debug_logging("Returning empty because  org_ids.empty? && org_and_memberships.business_memberships.empty?", "organization_ids_restricting_pat_lifetime")
          return []
        end

        business_memberships = org_and_memberships.business_memberships
        if business_memberships.any?
          # Get IDs of businesses that restrict access on orgs.
          business_ids = business_memberships.map(&:business_id).uniq
          business_ids = business_ids_with_pat_lifetime_restricted_by_limit(business_ids: business_ids, lifetime_limit: pat_lifetime, pat_type: pat_type)

          if org_ids.empty? && business_ids.empty?
            policy_debug_logging("Returning empty because org_ids.empty? && business_ids.empty?", "organization_ids_restricting_pat_lifetime")
            return []
          end

          # Only keep memberships where the org is restricted by the business.
          business_memberships = business_memberships.filter { |membership| business_ids.include?(membership.business_id) }

          # Businesses the actor administrates and exempt administrators.
          business_ids_exempting_actor = business_ids_with_pat_lifetime_limit_exemptions(pat_type: pat_type)

          # Only keep memberships where the actor is not exempted from the limit.
          business_memberships = business_memberships.filter { |membership| business_ids_exempting_actor.exclude?(membership.business_id) }

          # And only keep org_ids where orgs are restricted directly, without
          # an owning protecting business entry.
          org_ids = org_ids.difference(business_memberships.map(&:organization_id))
          policy_debug_logging("org_ids after difference", "organization_ids_restricting_pat_lifetime", {
            "gh.org_ids" => org_ids,
          })

          if org_ids.empty? && business_memberships.empty?
            policy_debug_logging("Returning empty because org_ids.empty? && org_and_memberships.business_memberships.empty?", "organization_ids_restricting_pat_lifetime")
            return []
          end
        end

        (business_memberships.map(&:organization_id) + org_ids).uniq.compact
      end

      # Private: Find all business_ids the actor administrates.
      #
      # Returns an Array.
      def business_ids_adminable_by_actor
        T.bind(self, T.any(
          ::ConditionalAccess::Policy::LegacyPersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokens::AppliedIn,
          ::ConditionalAccess::Policy::PersonalAccessTokensExpirationLimit::AppliedIn
        ))

        return @business_ids_adminable_by if defined?(@business_ids_adminable_by)

        @business_ids_adminable_by = actor.business_ids(membership_type: :admin) + actor.business_ids(membership_type: :billing_manager)
      end

      # Private: Filter all the business ids that have enabled the given configuration
      #
      # Returns an Array.
      def business_ids_with_configuration_enabled(business_ids, configuration_key)
        business_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
          Configuration::Entry.targeting_business_ids(grouped_ids)
            .named(configuration_key)
            .with_true_value
            .pluck(:target_id)
        end
      end

      # Private: Filter all the organization ids that have enabled the given configuration
      # access for themselves and their organizations.
      #
      # Returns an Array.
      def organization_ids_with_configuration_enabled(organization_ids, configuration_key)
        organization_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
          Configuration::Entry.targeting_user_ids(grouped_ids)
            .named(configuration_key)
            .with_true_value
            .pluck(:target_id)
        end
      end

      def organization_ids_with_pat_lifetime_restricted_by_limit(organization_ids:, lifetime_limit:, pat_type:)
        # If the PAT has no expiration, it would be restricted by any limit
        if lifetime_limit == :unlimited
          organization_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
            Configuration::Entry.targeting_user_ids(grouped_ids)
              .named(configuration_key_for_pat_lifetime(pat_type))
              .pluck(:target_id)
          end
        else
          organization_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
            Configuration::Entry.targeting_user_ids(grouped_ids)
              .named(configuration_key_for_pat_lifetime(pat_type))
              .with_value_less_than(lifetime_limit)
              .pluck(:target_id)
          end
        end
      end

      def business_ids_with_pat_lifetime_restricted_by_limit(business_ids:, pat_type:, lifetime_limit:)
        # If the PAT has no expiration, it would be restricted by any limit
        if lifetime_limit == :unlimited
          business_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
            Configuration::Entry.targeting_business_ids(grouped_ids)
              .named(configuration_key_for_pat_lifetime(pat_type))
              .pluck(:target_id)
          end
        else
          business_ids.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
            Configuration::Entry.targeting_business_ids(grouped_ids)
              .named(configuration_key_for_pat_lifetime(pat_type))
              .with_value_less_than(lifetime_limit)
              .pluck(:target_id)
          end
        end
      end

      def business_ids_with_pat_lifetime_limit_exemptions(pat_type:)
        business_ids_adminable_by_actor.in_groups_of(BATCH_SIZE, false).flat_map do |grouped_ids|
          Configuration::Entry.targeting_business_ids(grouped_ids)
          .named(configuration_key_for_pat_lifetime_exemption(pat_type))
          .with_true_value
          .pluck(:target_id)
        end
      end

      # Internal: Find all of the actor's associated org_ids and business memberships
      #
      # @return ActorOrganizationsAndBusinessMemberships
      def actor_organization_ids_and_business_memberships(actor)
        if FeatureFlag.vexi.enabled?(:evaluate_pat_filter_debug_logging, default: false)
          policy_debug_logging("actor ability delegate", "actor_organization_ids_and_business_memberships", {
            "gh.actor.ability_delegate" => actor.ability_delegate,
            "gh.actor.new_record" => actor.new_record?,
          })
        end
        policy_debug_logging("Starting method", "actor_organization_ids_and_business_memberships")
        return @actor_organization_ids_and_business_memberships if defined?(@actor_organization_ids_and_business_memberships)
        policy_debug_logging("Passed memoization", "actor_organization_ids_and_business_memberships")

        user_direct_org_ids = actor.organization_ids || []
        policy_debug_logging("user_direct_org_ids", "actor_organization_ids_and_business_memberships", {
          "gh.user_direct_org_ids" => user_direct_org_ids,
        })

        user_org_ids = user_direct_org_ids.union(actor.org_ids_via_business_membership)
        policy_debug_logging("actor.org_ids_via_business_membership", "actor_organization_ids_and_business_memberships", {
          "gh.actor.org_ids_via_business_membership" => actor.org_ids_via_business_membership,
        })

        if user_org_ids.empty?
          policy_debug_logging("user_org_ids.empty? is true", "actor_organization_ids_and_business_memberships")
          @actor_organization_ids_and_business_memberships = ActorOrganizationsAndBusinessMemberships.new([], [], [])

          return @actor_organization_ids_and_business_memberships
        end

        business_memberships = user_org_ids.in_groups_of(BATCH_SIZE, false).flat_map do |org_ids|
          Business::OrganizationMembership.where(organization_id: org_ids).select(:business_id, :organization_id)
        end

        policy_debug_logging("business_memberships", "actor_organization_ids_and_business_memberships", {
          "gh.business_memberships" => business_memberships,
        })

        @actor_organization_ids_and_business_memberships = ActorOrganizationsAndBusinessMemberships.new(user_org_ids, user_direct_org_ids, business_memberships)
      end

      def actor_organization_ids_and_business_memberships_candidate(actor, targets)
        return @actor_organization_ids_and_business_memberships_candidate if defined?(@actor_organization_ids_and_business_memberships_candidate)

        target_org_ids = targets.select { |target| target.instance_of?(Organization) }
                                  .map(&:id)
                                  .uniq
        user_direct_org_ids = actor.organization_ids & target_org_ids

        user_indirect_org_ids = if GitHub.single_business_environment?
          # In a single business environment, we want to avoid org_ids_via_business_membership
          # because it can return too many orgs. This if-else is an optimized version of it.
          Organization.where(id: target_org_ids).pluck(:id)
        else
          actor.org_ids_via_business_membership
        end

        actor_affiliated_organization_ids = user_direct_org_ids | user_indirect_org_ids
        applicable_organization_ids = target_org_ids & actor_affiliated_organization_ids

        if applicable_organization_ids.empty?
          @actor_organization_ids_and_business_memberships_candidate = ActorOrganizationsAndBusinessMemberships.new([], [], [])

          return @actor_organization_ids_and_business_memberships_candidate
        end

        business_memberships = applicable_organization_ids.in_groups_of(BATCH_SIZE, false).flat_map do |org_ids|
          Business::OrganizationMembership.where(organization_id: org_ids).select(:business_id, :organization_id)
        end

        @actor_organization_ids_and_business_memberships_candidate = ActorOrganizationsAndBusinessMemberships.new(applicable_organization_ids, user_direct_org_ids, business_memberships)
      end

      def configuration_key_for_pat_lifetime(pat_type)
        pat_type == ProgrammaticAccessTokenType::FineGrained ? Configurable::PersonalAccessTokenExpirationLimit::FG_PAT_KEY : Configurable::PersonalAccessTokenExpirationLimit::PAT_CLASSIC_KEY
      end

      def configuration_key_for_pat_lifetime_exemption(pat_type)
        pat_type == ProgrammaticAccessTokenType::FineGrained ? Configurable::PersonalAccessTokenExpirationLimitExemptionEnabled::FG_PAT_KEY : Configurable::PersonalAccessTokenExpirationLimitExemptionEnabled::PAT_CLASSIC_KEY
      end

      def policy_debug_logging(msg, function, options = {})
        nil
      end
    end
  end
end
