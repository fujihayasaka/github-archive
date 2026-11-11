# typed: true
# frozen_string_literal: true

module ControllerMethods
  module Oauth
    extend T::Helpers

    abstract!

    sig { abstract.returns(T.nilable(T.any(Integration, OauthApplication))) }
    def application; end

    requires_ancestor { ApplicationController }

    def actor_id
      current_user.id if logged_in?
    end

    def check_eligibility
      return if Apps::Privileged.capable?(:skip_oauth_user_eligibility_check, app: application)
      return unless current_user.spammy? || current_user.must_verify_email?

      if current_user.spammy?
        flash[:error] = "This account is flagged, and therefore cannot authorize a third party application."
        return redirect_to dashboard_path
      end

      if current_user.must_verify_email?
        flash[:error] = "Authorizing an application requires a verified email address."
        render_email_verification_required
      end
    end

    def cid
      if cookies[:_octo] =~ /\A[^.]+\.[^.]+\.\d+\.\d+\z/
        cookies[:_octo].split(".")[2..3].join(".")
      end
    end

    def check_visibility
      return if GitHub.enterprise?
      return if application.is_a?(OauthApplication)

      integration = T.cast(application, Integration)
      return if integration.public_visibility?

      # TODO: this is what we should do but it's a breaking change
      # return if integration.private? && integration.owner == current_user
      # Until then, maintain current behavior for private integrations
      return if integration.private_visibility?

      return if integration.internal_visibility? && non_outside_collaborator_member?(integration.owner)

      # We shouldn't get here, if we do let's bounce in a fit of uncertainty.
      render_404
    end

    def check_app_enterprise_association
      # GitHub Enterprise has its own protections.
      return if GitHub.enterprise?
      app = T.cast(application, T.any(OauthApplication, Integration))

      # If we're in Proxima and a tenant is set and the owner is not found then
      # we know the app is not associated with the tenant and we should 404.
      #
      # There's no other valid reason for an App to not have an owner.
      if GitHub.multi_tenant_enterprise?
        if app.user.nil?
          log_oauth_authorization_blocked(app, "owner_is_enterprise_managed", "multi_tenant_enterprise_no_owner")
          return render_404
        end

        return
      end

      # return unless the app is owned by an owner in EMU mode
      owner_is_enterprise_managed = if T.must(app.owner).user?
        app.owner&.is_enterprise_managed?
      else
        app.owner&.enterprise_managed_user_enabled?
      end
      return unless owner_is_enterprise_managed

      unless current_user.is_enterprise_managed?
        log_oauth_authorization_blocked(app, "owner_is_enterprise_managed", "user_not_enterprise_managed")
        return render_404
      end

      owner_biz = if app.owner.business?
        app.owner
      elsif app.owner.organization?
        app.owner.business
      else
        app.owner.enterprise_managed_business
      end

      current_user_biz = current_user.enterprise_managed_business

      # If the app is owned by an enterprise and the user is not a member of

      # only allow EMUs associated with the enterprise to authorize the app
      return if current_user_biz == owner_biz

      log_oauth_authorization_blocked(app, "owner_is_enterprise_managed", "enterprise_mismatch")
      render_404
    end

    def check_app_ownership
      return unless application.is_a?(Integration)
      app = T.cast(application, Integration)

      if app.private_visibility?

        if app.owner.user?
          # private user-owned integrations are only visible to the owner
          return if app.owner == current_user
          log_oauth_authorization_blocked(app, "private_app_ownership", "user_not_app_owner")
        elsif app.owner.organization?
          # private org-owned integrations are visible to organization members
          return if app.owner.member?(current_user, include_indirect_abilities: app.owner.indirect_abilities_enabled?)
          log_oauth_authorization_blocked(app, "private_app_ownership", "user_not_org_member")
        end

        render_404
      end
    end

    def conditional_sudo_filter
      return unless oauth_access_authorized?
      return unless (@scopes & Api::AccessControl.sudo_protected_scope_names).any?

      sudo_filter
    end

    def instrument_integration_listing
      return unless application&.integration_listing

      integration_listing = T.must(application).integration_listing
      GitHub.instrument("integration.listing_authorized", {
        dimensions: {
          id: T.must(integration_listing).id,
          cid: cid,
          actor_id: actor_id,
        },
      })
    end

    def oauth_access_authorized?
      %w[1 Approve].include? params[:authorize]
    end

    def reject_dangerous_requests
      # TODO As we change this code over time, move the business logic out of this
      # controller and into domain objects (like OauthAuthorizationRequest). Allow
      # the controller to function solely as a traffic cop.

      @authorization_request = OauthAuthorizationRequest.new(
        user: current_user,
        application: application,
        scopes: @scopes
      )

      return unless @authorization_request.dangerous_to_github?
      render "oauth/dangerous_to_github", locals: { request: @authorization_request }
    end

    def reject_suspended_applications
      raise NotImplementedError
    end

    def secret_last_eight(secret)
      secret = secret.to_s
      return secret if secret.length < 8

      secret.to_s[-8..-1]
    end

    def show_sso_selection?(application)
      return false if params.fetch(:skip_sso, false)
      unauthorized_saml_organizations_for_application.any?
    end

    def unauthorized_saml_organizations_for_application
      return @unauthorized_saml_organizations if defined?(@unauthorized_saml_organizations)

      @unauthorized_saml_organizations = []
      unauthorized_saml_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      return @unauthorized_saml_organizations if unauthorized_saml_org_ids.empty?

      @unauthorized_saml_organizations = if application.is_a?(Integration)
        integration = T.cast(application, Integration)
        target_ids = integration.installations.where(target_id: unauthorized_saml_org_ids, target_type: "User").pluck(:target_id)

        Organization.includes(:business).where(id: target_ids)
      else
        Organization.oauth_app_policy_met_by(application).includes(:business).where(id: unauthorized_saml_org_ids)
      end.to_a

      @unauthorized_saml_organizations
    end

    private

    # We want to exclude users that have a BUA with only the :outside_collaborator role
    def non_outside_collaborator_member?(business)
      with_roles = current_user
      .business_user_accounts
      .roles([:member, :owner])
      .where(business: business)

      # Then query for unaffiliated users
      unaffiliated = current_user
        .business_user_accounts
        .exclusive_unaffiliated_role
        .where(business: business)

      # Combine the results and check if any exist
      (with_roles.or(unaffiliated)).exists?
    end

    def reject_attribution_only_system_identities
      render_404 if Apps::Privileged.capable?(:attribution_only_system_identity, app: application)
    end

    def log_oauth_authorization_blocked(app, enforcement_type, reason)
      GitHub.dogstats.increment("oauth.authorization.page_blocked", tags: [
        "enforcement_type:#{enforcement_type}",
        "reason:#{reason}",
      ])
      GitHub.logger.info(
        "OAuth authorization blocked",
        "gh.oauth.authorization.enforcement_type" => enforcement_type,
        "gh.oauth.authorization.block_reason" => reason,
        "gh.oauth.application.id" => app.id,
        "gh.oauth.application.name" => app.name,
        "gh.oauth.application.type" => app.class.name,
      )
    end
  end
end
