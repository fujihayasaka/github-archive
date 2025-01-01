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
        saml_filter_debug_logging("query on the business", "authorized_businesses")
        return [] if @user.nil?

        businesses = authorized_organizations(include_businesses: true).map do |org|
          org.business if org.sso_enabled_on_business?
        end.compact.uniq

        protected_biz_ids = protected_business_ids
        authorized_saml_businesses = businesses.reject do |biz|
          # protected_biz_ids excludes business that belongs to an org that the user is not SSO authorized for.
          # We need to allow access to these businesses for the user to be able to access internal and public resources from these orgs.

          if biz.feature_flag_enabled?(:saml_scope_private_resources_to_business, default: false)
            protected_biz_ids.include?(biz.id)
          else
            next
          end
        end

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

        cutoff_time = Time.at((Time.now.to_f / 60).round * 60)

        if @user && @user.is_enterprise_managed? && @user.enterprise_managed_business.oidc_enabled?
          saml_filter_debug_logging("query_params", "authorized_org_ids_from_session", {
            cutoff_time: cutoff_time,
            oidc_query: true
          })
          # If the user is enterprise managed and the business has OIDC enabled,
          # We don't need to check for authorized SAML orgs, as the OIDC provider is only used for the business.
          # In this case, we return the orgs that belongs to the business that the user is a member of.
          authorized_business_oidc_org_ids = Organization.
            joins({ business: { oidc_provider: { external_identities: :sessions } } }).
            where("external_identity_sessions.user_session_id = ?", @session.id).
            where("external_identity_sessions.expires_at > ?", cutoff_time)

          @authorized_org_ids_from_session = authorized_business_oidc_org_ids.pluck(:id).uniq
        else
          saml_filter_debug_logging("query_params", "authorized_org_ids_from_session", {
            cutoff_time: cutoff_time,
            oidc_query: false
          })
          authorized_saml_org_ids = Organization.
            joins({ saml_provider: { external_identities: :sessions } }).
            where("external_identity_sessions.user_session_id = ?", @session.id).
            where("external_identity_sessions.expires_at > ?", cutoff_time)

          authorized_business_saml_org_ids = Organization.
            joins({ business: { saml_provider: { external_identities: :sessions } } }).
            where("external_identity_sessions.user_session_id = ?", @session.id).
            where("external_identity_sessions.expires_at > ?", cutoff_time)

          orgs_ids = authorized_saml_org_ids.pluck(:id).union(authorized_business_saml_org_ids.pluck(:id)).uniq
          orgs_ids += @session.user.organizations.where(id: non_enforceable_saml_orgs_ids).pluck(:id) if @consider_non_enforceable_targets

          @authorized_org_ids_from_session = orgs_ids
        end
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
          ProgrammaticAccessGrant.
            with_target_type_and_access("Organization", @fine_grained_pat).
            where(organization_id: saml_org_ids).
            pluck(:organization_id)

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

        org_ids = if @user.feature_flag_enabled?(:cap_filter_consider_outside_collabs, default: false)
          @user.authorizable_organization_ids
        else
          @user.organization_ids
        end

        @saml_org_ids ||= Organization::SamlEnforcementPolicy.saml_organization_ids(org_ids, @user)
      end

      def non_enforceable_saml_orgs_ids
        return [] if @user.nil?
        @user.organization_ids - saml_org_ids
      end

      def saml_filter_debug_logging(msg, function, options = {})
        return unless ::FeatureFlag.vexi.enabled?(:saml_filter_logging, default: false)

        GitHub.logger.info(
          msg,
          {
            "code.function": function,
            "gh.request_id": GitHub.context[:request_id],
            **options
          }
        )
      end
    end
  end
end
