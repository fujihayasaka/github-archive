# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Authorization
    class SAML
      include Scientist

      # Create a Platform::Authorization::SAML object.
      # The direct use of this object is deprecated.
      # Consider using a Conditional Access Policy Framework (CAP) methods
      # e.g. `cap_unauthorized_organization_ids(only: :saml)` instead.
      # Read how to update a conditional access filtering callsite to use CAP Framework:
      # https://github.com/github/authorization/blob/main/docs/cap/update-callsite-to-cap-filtering.md
      #
      # user - User representing the actor for the request.
      # session - UserSession representing the actor session for the request.
      # remote_token_auth - Boolean representing whether remote token auth is
      #   being used for this request. Defaults to false.
      #   See GitHub::Authentication::SignedAuthToken.
      # consider_non_enforceable_targets - Boolean defining wether to include organizations/businesses for which
      #   the actor doesn't need SAML to be enforced. E.g. collaborator of a SAML org, member of a non-SAML business.
      #   This flag is being used to rollout new behaviour only to the Conditional Access Policy filtering callsites.
      #   This flag should not be used for any other action than to guard the new behaviour.
      #   It is not meant to be a permanent addition to the class. See https://github.com/github/github/pull/154380
      def initialize(user: nil, session: nil, remote_token_auth: false,
                     consider_non_enforceable_targets: false, consider_biz_only_membership: false)
        if user && session
          raise ArgumentError, "You must supply user or session, not both"
        end

        @session = session
        @user = user || session&.user
        @remote_token_auth = remote_token_auth

        if (oauth_access = @user&.oauth_access)
          @oauth_access = oauth_access
        elsif (fine_grained_pat = @user&.programmatic_access)
          @fine_grained_pat = fine_grained_pat
        end

        @consider_non_enforceable_targets = consider_non_enforceable_targets
        @consider_biz_only_membership = consider_biz_only_membership
      end

      # Organizations for which the request (session or token based) is authorized.
      def authorized_organization_ids
        case
        when @session
          # include business orgs that the user does not belong to directly but is authorized via the business IdP
          authorized_org_ids_from_session
        when @oauth_access
          # tokens must be authorized individually per-organization,
          # unlike session-based access which grants access to other orgs inside the same business.
          authorized_org_ids_from_oauth
        when @fine_grained_pat
          # tokens are authorized on a per-grant basis.
          authorized_org_ids_from_fine_grained_pat
        else
          return non_enforceable_saml_orgs_ids if @consider_non_enforceable_targets
          []
        end
      end

      def protected_organization_ids
        return [] if @user.blank?

        if (oauth_access = @user.oauth_access)
          return [] unless oauth_access.saml_enforceable?
        end

        return [] if @remote_token_auth
        return [] if @user.is_a?(Bot)

        return saml_org_ids if saml_org_ids.empty?

        saml_org_ids - authorized_organization_ids
      end

      def protected_organizations(include_businesses: false)
        query = Organization.where(id: protected_organization_ids)

        if include_businesses
          query = query.includes(:business)
        end

        query
      end

      # Consider using a Conditional Access Policy(CAP) method alternative if your intention is to filter resource(s).
      #
      # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filtering
      def protected_business_ids
        protected_organizations(include_businesses: true).map do |org|
          org.business.id if org.sso_enabled_on_business?
        end.compact.uniq
      end

      # Consider using a Conditional Access Policy(CAP) method alternative if your intention is to filter resource(s).
      #
      # Read more: https://thehub.github.com/engineering/development-and-ops/dotcom/cap/update-callsite-to-cap-filterin
      def authorized_organizations(include_businesses: false)
        query = Organization.where(id: authorized_organization_ids)

        if include_businesses
          query = query.includes(:business)
        end

        query
      end

      def authorized_businesses
        return [] if @user.nil?

        businesses = authorized_organizations(include_businesses: true).map do |org|
          org.business if org.sso_enabled_on_business?
        end.compact.uniq

        protected_biz_ids = protected_business_ids
        authorized_saml_businesses = businesses.reject { |biz| protected_biz_ids.include?(biz.id) }

        result = authorized_saml_businesses

        non_saml_businesses = @user.businesses.reject { |biz| biz.saml_sso_enabled? }
        if @consider_non_enforceable_targets
          result = (result + non_saml_businesses).uniq
        end
        if @consider_biz_only_membership
          admin_biz = @user.businesses(membership_type: :admin)
          billing_manager_biz = @user.businesses(membership_type: :billing_manager)

          # add SAML businesses where the user is either an admin or a billing manager
          saml_businesses = (admin_biz + billing_manager_biz).uniq - non_saml_businesses
          biz_only_membership  = saml_businesses.reject { |biz| protected_biz_ids.include?(biz.id) }

          result = (result + biz_only_membership).uniq
        end
        result
      end

      # Return the "SAML orgs" for the user.
      #
      # "SAML orgs" are defined as those where either:
      # - The org has a SAML provider configured and enforced.
      # - The org has a SAML provider configured and the user already has
      #   an external identity.
      # - The org has an owning business that has a SAML provider configured
      #   and the user has an external identity.
      #
      # Returns an ActiveRecord::Relation containing the "SAML orgs".
      def saml_organizations
        Organization.where id: saml_org_ids
      end

      private

      # From a user_session, get all active external_identity_sessions that are
      # associated, either via a SAML provider at the org level or at the owning
      # business level.
      #
      # These external_identity_sessions can map back up to the organizations
      # for which they are valid. From there, we have a list of orgs that the
      # user's session is allowed to access.
      def authorized_org_ids_from_session
        return @authorized_org_ids_from_session if defined?(@authorized_org_ids_from_session)

        authorized_saml_org_ids = Organization.
          joins({ saml_provider: { external_identities: :sessions } }).
          where("external_identity_sessions.user_session_id = ?", @session.id).
          where("external_identity_sessions.expires_at > ?", Time.at((Time.now.to_f / 60).round * 60))

        authorized_business_saml_org_ids = Organization.
          joins({ business: { saml_provider: { external_identities: :sessions } } }).
          where("external_identity_sessions.user_session_id = ?", @session.id).
          where("external_identity_sessions.expires_at > ?", Time.at((Time.now.to_f / 60).round * 60))

        orgs_ids = authorized_saml_org_ids.pluck(:id).union(authorized_business_saml_org_ids.pluck(:id)).uniq
        orgs_ids += @session.user.organizations.where(id: non_enforceable_saml_orgs_ids).pluck(:id) if @consider_non_enforceable_targets

        @authorized_org_ids_from_session = orgs_ids
      end

      # From an OAuth token, get all organizations for which the token has been
      # explicitly allowlisted.
      def authorized_org_ids_from_oauth
        unless @oauth_access.saml_enforceable?
          return saml_org_ids + non_enforceable_saml_orgs_ids if @consider_non_enforceable_targets
          return saml_org_ids
        end
        authorized_saml_org_ids = Organization::CredentialAuthorization.active.
          by_credential(credential: @oauth_access).
          where(organization_id: saml_org_ids).
          pluck(:organization_id)

        return authorized_saml_org_ids + non_enforceable_saml_orgs_ids if @consider_non_enforceable_targets
        authorized_saml_org_ids
      end

      def authorized_org_ids_from_fine_grained_pat
        authorized_saml_org_ids =
          if @user.feature_enabled?(:saml_org_ids_via_fg_pats)
            ProgrammaticAccessGrant.
              with_target_type_and_access("Organization", @fine_grained_pat).
              where(organization_id: saml_org_ids).
              pluck(:organization_id)
          else
            []
          end

        return authorized_saml_org_ids + non_enforceable_saml_orgs_ids if @consider_non_enforceable_targets
        authorized_saml_org_ids
      end

      # Find all of the organizations the user is member of or collaborator within that meet these criteria:
      #
      # - Where the org has a SAML provider configured and enforced.
      # - Where the org has a SAML provider configured but not enforced, and the user already has
      #   an external identity.
      # - Where the org has an owning business that has a SAML provider configured
      def saml_org_ids
        return @saml_org_ids if defined?(@saml_org_ids)

        # Anonymous access falls back to existing access control checks
        return Organization.none if @user.nil?

        # GHES with SCIM enables a SAML provider on the global business, but is exempt from this enforcement
        return Organization.none if GitHub.single_business_environment? && GitHub.global_business&.enterprise_server_scim_enabled?

        org_ids = if @user.feature_enabled?(:cap_filter_consider_outside_collabs)
          @user.authorizable_organization_ids
        else
          @user.organization_ids
        end

        # Find only organizations the user is a direct member of
        # and only those organizations belonging to a business
        business_join_clause = <<-SQL.squish
          INNER JOIN business_organization_memberships
            ON business_organization_memberships.organization_id = users.id
          LEFT OUTER JOIN business_saml_providers
            ON business_saml_providers.business_id = business_organization_memberships.business_id
        SQL

        # Find only organizations the user is a direct member of
        # and only those organizations belonging to a business with a SAML
        # provider configured
        business_conditions = <<-SQL.squish
          users.id IN (:organization_ids)
        SQL

        business_organizations =
          Organization.joins(business_join_clause).
            where(business_conditions, organization_ids: org_ids).
            pluck(:id, "business_saml_providers.business_id")

        # Find only organizations with a SAML provider configured
        business_org_ids = business_organizations.map { |id, business_id| id if business_id.present? }.compact
        # Find only organizations with a without SAML provider configured
        # those will have to be included if the plan does not match GitHub::Plan::BUSINESS_PLUS
        business_org_ids_no_saml = business_organizations.map { |id, business_id| id unless business_id.present? }.compact

        # Since we already have organizations with a SAML provider configured on a business
        # we can exclude those from the direct organizations query
        org_ids -= business_org_ids

        # no organizations without a business membership, no need to continue
        return business_org_ids.uniq if org_ids.empty?

        # Select organizations with their configured SAML providers
        # and join the user's external identities when present
        # no need to a left join to business_saml_providers since
        # all of those ids are in this array business_org_ids_no_saml
        org_join_clause = <<-SQL.squish
          INNER JOIN organization_saml_providers
            ON organization_saml_providers.organization_id = users.id
          LEFT JOIN external_identities
            ON external_identities.provider_id = organization_saml_providers.id
              AND external_identities.provider_type = "Organization::SamlProvider"
        SQL

        # Find only organizations the user is a direct member of
        # and only those organizations that enforce SSO or any the
        # member has an external identity linked with
        org_conditions = <<-SQL.squish
          (
            plan = :plan OR
            users.id IN (:business_org_ids)
          )
          AND users.id IN (:organization_ids)
          AND (
            organization_saml_providers.enforced = 1
            OR external_identities.user_id = :user_id
          )
        SQL

        direct_org_ids =
          Organization.joins(org_join_clause)
            .where(org_conditions, organization_ids: org_ids, business_org_ids: business_org_ids_no_saml, user_id: @user.id, plan: GitHub::Plan::BUSINESS_PLUS)
            .group(:id)

        @saml_org_ids ||= direct_org_ids.pluck(:id).union(business_org_ids).uniq
      end

      def non_enforceable_saml_orgs_ids
        return [] if @user.nil?
        @user.organization_ids - saml_org_ids
      end
    end
  end
end
