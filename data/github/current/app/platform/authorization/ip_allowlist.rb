# typed: true
# frozen_string_literal: true

module Platform
  module Authorization
    class IpAllowlist

      # Create a Platform::Authorization::IpAllowlist object.
      # The direct use of this Object is deprecated, consider using Conditional Access Policy Framework (CAP) methods
      # e.g. `cap_unauthorized_organization_ids(only: :ip_allowlist)`
      # instead.
      # Read how to update a conditional access filtering callsite to use CAP Framework:
      # https://github.com/github/authorization/blob/main/docs/cap/update-callsite-to-cap-filtering.md
      #
      # user - User representing the actor for the request.
      # ip - String representing the actor's originating IP address.
      # remote_token_auth - Boolean representing whether remote token auth is
      #   being used for this request. Defaults to false.
      #   See GitHub::Authentication::SignedAuthToken.
      def initialize(user: nil, ip: nil, remote_token_auth: false)
        @user = user
        @remote_token_auth = remote_token_auth
        @ip = ip
      end

      # Public: Get all organizations that the user can't access from
      # the IP address due to IP allow list enforcement.
      #
      # include_businesses - Boolean whether or not to load the business
      #   association on an org. Defaults to false.
      #
      # Returns ActiveRecord::Relation.
      def protected_organizations(include_businesses: false)
        query = Organization.where(id: protected_organization_ids)

        if include_businesses
          query = query.includes(:business)
        end

        query
      end

      def protected_businesses
        protected_organizations(include_businesses: true).map do |org|
          org.business if org.ip_allowlist_enabled?
        end.compact.uniq
      end

      # Public: Get the IDs of all organizations that the user can't access from
      # the IP address due to IP allow list enforcement.
      #
      # The logic of this method is specifically written to avoid N+1 queries
      # which were a problem when Organization#ip_allowlist_enabled? was
      # repeatedly being called.
      #
      # Returns Array of Integer.
      def protected_organization_ids
        return [] if @ip.blank?
        return [] if @user.blank?
        return [] if @user.using_oauth_application?
        return [] if @user.using_auth_via_granular_actor?
        return [] if @remote_token_auth
        return [] if @user.can_have_granular_permissions?

        return @protected_organization_ids if defined?(@protected_organization_ids)

        user_direct_org_ids = @user.organization_ids || []
        user_org_ids = user_direct_org_ids.union(@user.org_ids_via_business_membership)
        return [] if user_org_ids.empty?

        business_memberships = Business::OrganizationMembership
          .where(organization_id: user_org_ids)
          .pluck(:business_id, :organization_id)

        # Get IDs of orgs protected directly at the org level.
        org_ids = Configuration::Entry.targeting_user_ids(user_direct_org_ids)
          .named(Configurable::IpAllowlistEnabled::KEY)
          .with_true_value
          .pluck(:target_id)
        return [] if org_ids.empty? && business_memberships.empty?

        if business_memberships.any?
          # Get IDs of businesses that protect orgs.
          business_ids = Configuration::Entry.targeting_business_ids(business_memberships.map(&:first).uniq)
            .named(Configurable::IpAllowlistEnabled::KEY)
            .with_true_value
            .pluck(:target_id)
          return [] if org_ids.empty? && business_ids.empty?
          # Only keep memberships where the org is protected by the business.
          business_memberships.keep_if { |membership| business_ids.include?(membership.first) }
          # And only keep org_ids where orgs are protected directly, without
          # an owning protecting business entry.
          org_ids.keep_if do |org_id|
            memberships = business_memberships.select { |membership| org_id == membership.second }
            memberships.empty?
          end
        end
        return [] if org_ids.empty? && business_memberships.empty?

        # Now that we know the orgs that have an IP allow list policy enabled,
        # check the active entries on each allow list to see which specific
        # orgs are protected based on the current IP address.

        # Only return orgs actually blocked by the owning business' allow list
        # or their own allow list.
        if business_memberships.any?
          business_membership_allowing_entries = IpAllowlistEntry.where(owner_type: "Business", owner_id: business_memberships.map(&:first).uniq)
            .or(IpAllowlistEntry.where(owner_type: "User", owner_id: business_memberships.map(&:second)))
            .active
            .matching_ip(@ip)
            .pluck(:owner_type, :owner_id)
          # Only keep memberships where there are no entries that allow access.
          business_memberships.keep_if do |membership|
            !business_membership_allowing_entries.include?(["Business", membership.first]) &&
              !business_membership_allowing_entries.include?(["User", membership.second])
          end
        end
        blocked_business_owned_org_ids = business_memberships.map(&:second)

        # Only return orgs actually blocked by their own allow list.
        if org_ids.any?
          allowed_org_ids = IpAllowlistEntry
            .where(owner_type: "User", owner_id: org_ids)
            .active
            .matching_ip(@ip)
            .pluck(:owner_id)
          org_ids.keep_if { |id| !allowed_org_ids.include?(id) }
        end

        @protected_organization_ids = (blocked_business_owned_org_ids + org_ids).uniq.compact
      end

      # Public: Get the IDs of all Users that the user can't access from
      # the IP address due to the IP allow list policy.
      #
      # Returns Array of Integer.
      def protected_user_ids
        return [] if @ip.blank?
        return [] if @user.blank?
        return [] if @user.using_oauth_application?
        return [] if @user.using_auth_via_granular_actor?
        return [] if @remote_token_auth
        return [] if @user.can_have_granular_permissions?

        return @protected_user_ids if defined?(@protected_user_ids)

        @protected_user_ids = []

        # If user is an EMU (Enterprise Managed User), return IDs for the EMU Business members
        # if the user can't access the Business due to IP allow list enforcement.
        if @user.is_enterprise_managed?
          business = @user.enterprise_managed_business
          return @protected_user_ids = [] unless business
          return @protected_user_ids = [] unless business.ip_allowlist_user_level_enforcement_enabled?
          return @protected_user_ids = [] unless business.ip_allowlist_enabled?
          return @protected_user_ids = [] if IpAllowlistEntry.usable_for(business).active.matching_ip(@ip).any?

          @protected_user_ids = business
            .user_accounts
            .includes(:user)
            .map { |account| account&.user&.id }.compact
        end

        @protected_user_ids
      end
    end
  end
end
