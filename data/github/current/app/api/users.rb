# typed: true
# frozen_string_literal: true

require "github/null_objects"

class Api::Users < Api::App
  include ReceiveSchemaWithOpenApi
  include FeatureFlagHelper

  map_to_service :apps, only: [ # rubocop:todo GitHub/MapToService
    "GET /user/installations"
  ]

  include Scientist

  USER_VIA_GITHUB_APP_ACCESS_ONLY = "You must authenticate with an access token authorized to a GitHub App in order to ".freeze

  # Get the authenticated User
  get "/user", operation_id: "users/get-authenticated" do
    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    options = {
      response_key        => true,
      :plan               => access_allowed?(:read_user_plan, resource: current_user, allow_integrations: false, allow_user_via_granular_actor: true),
      :last_modified      => calc_last_modified_for_object(current_user),
      :current_user       => current_user,
      :check_email_claimed => !GitHub.multi_tenant_enterprise? && !GitHub.enterprise?,
    }

    deliver :user_hash, current_user, options
  end

  MarketplacePurchasesQuery = PlatformClient.parse <<-'GRAPHQL'
    query($planBulletsLimit: Int!, $marketplaceListingId: ID!, $subscriptionItemLimit: Int!, $numericPage: Int) {
      viewer {
        marketplaceSubscriptions(marketplaceListingId: $marketplaceListingId, first: $subscriptionItemLimit, numericPage: $numericPage) {
          totalCount
          edges {
            node {
              ...Api::Serializer::MarketplaceListingDependency::SubscriptionItemFragment
            }
          }
        }
      }
    }
  GRAPHQL

  # Update the authenticated User
  verbs :patch, :post, "/user", operation_id: "users/update-authenticated" do
    control_access :update_user_profile,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # Introducing strict validation of the user.update-authentication
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("user", "update-authenticated", skip_validation: true)

    keys = [
      :name,
      :email,
      :blog,
      :company,
      :location,
      :hireable,
      :bio,
      :twitter_username,
    ]

    attributes = attr(data,
      *keys,
      { prefix: "profile_" },
    )

    if current_user.is_enterprise_managed?
      attributes = attributes.delete_if { |attribute, _val| attribute.to_sym.in?(User::EnterpriseManagedDependency::ENTERPRISE_MANAGED_ATTRIBUTES) }
    end

    if current_user.update(attributes)
      deliver :user_hash, current_user, private: true
    else
      deliver_error 422,
        errors: current_user.errors,
        documentation_url: "/rest/reference/users#update-the-authenticated-user"
    end
  end

  get "/user/marketplace_purchases", operation_id: "apps/list-subscriptions-for-authenticated-user" do
    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    return deliver_raw([]) unless current_user.oauth_access&.application

    marketplace_listing = current_user.oauth_access.application.marketplace_listing
    return deliver_raw([]) unless marketplace_listing

    variables = {
      "planBulletsLimit"     => Marketplace::ListingPlanBullet::BULLET_LIMIT_PER_LISTING_PLAN,
      "marketplaceListingId" => marketplace_listing.global_relay_id,
      "subscriptionItemLimit" => pagination[:per_page] || MAX_PER_PAGE,
      "numericPage" => pagination[:page],
    }

    results = platform_execute(MarketplacePurchasesQuery, variables: variables)

    error_type = results.errors.any? && results.errors.details["data"]&.first["type"]
    deliver_error! 404 if error_type == "NOT_FOUND"

    subscriptions = results.data.viewer.marketplace_subscriptions
    subscription_items = subscriptions.edges.map(&:node)
    paginator.collection_size = subscriptions.total_count

    deliver :graphql_marketplace_purchase_hash, subscription_items
  end

  # List a user's Marketplace purchases
  get "/user/marketplace_purchases/stubbed", operation_id: "apps/list-subscriptions-for-authenticated-user-stubbed" do
    if GitHub.flipper[:marketplace_stub_apis_return_404].enabled?
      deliver_error!(404)
    end

    control_access :read_user,
      resource: current_user,
      challenge: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    deliver_raw Marketplace::StubbedResponse.purchases
  end

  # List the installations the authorized user has access to.
  get "/user/installations", operation_id: "apps/list-installations-for-authenticated-user" do
    set_forbidden_message USER_VIA_GITHUB_APP_ACCESS_ONLY + "list installations"

    control_access :read_user_installations,
      resource: current_user,
      challenge: true,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    unauthorized_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations)
    installations = current_integration.installations.with_user(current_user)

    if unauthorized_org_ids.any?
      unauthorized_sso_org_ids = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: :saml)
      unauthorized_target_ids = installations.where(target_type: "User", target_id: unauthorized_sso_org_ids).pluck(:target_id)

      set_sso_partial_results_header(unauthorized_target_ids) if unauthorized_target_ids.any?
    end

    installations = installations.where.not(target_id: unauthorized_org_ids)
    installations = paginate_rel(installations)

    GitHub::PrefillAssociations.prefill_associations(
      installations,
      [:target, :event_records, :user_suspended_by, :version, :integration],
      available_records: [current_integration]
    )

    deliver :integration_installations_hash, {
      integration_installations: installations,
      total_count: installations.count,
    }
  end

  # Browser Session Checks
  #
  #

  # Verify if a browser session is still valid for user and OAuth application
  get "/user/sessions/active", operation_id: :internal do
    @route_owner = "@github/identity"
    control_access :read_user, resource: current_user, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    message = "This API can only be accessed with OAuth tokens."
    set_forbidden_message(message, true)
    check_authorization { logged_in? && current_user.using_oauth? }

    if current_user.active_browser_session_for_application?(current_app,
                                                            params[:browser_session_id])
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  get "/users", operation_id: "users/list", resolve_tenant_context: :resolve_tenant_from_current_user do
    control_access :read_user_public,
      resource: Platform::PublicResource.new, # rubocop:disable GitHub/PublicResource
      allow_integrations: true,
      allow_user_via_granular_actor: true

    users = User.dump_page(cursor: params[:since].to_i, page_size: per_page)
    @links.add_dump_pagination(users.last)

    GitHub::PrefillAssociations.prefill_associations(
      users.filter { |u| u.is_a?(Bot) },
      { integration: :owner }
    )
    users = users.reject { |u| u.is_a?(ProgrammaticAccessBot) }

    if feature_enabled_globally_or_for_user?(feature_name: :prevent_emu_user_enumeration)
      users = reject_emu_users(users)
    end

    deliver(:user_hash, users)
  end

  # Get a single User
  get "/user/:user_id", operation_ids: ["users/get-by-username", "users/get-by-id"], resolve_tenant_context: :resolve_tenant_from_current_user do
    user = find_user!

    control_access :read_user_public,
      resource: Platform::PublicResource.new(resource: user),
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      enforce_oauth_app_policy: false


    if GitHub.spamminess_check_enabled? && user.spammy?
      control_access :read_spammy_state, resource: user, allow_integrations: true, allow_user_via_granular_actor: true
    end

    # Ensure we are not leaking EMU bot information to unauthorized users
    if user.bot?
      control_access :read_requested_bot_user,
        resource: user,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: false
    end

    deliver(
      :user_hash,
      user,
      response_key(user) => true,
      :plan => access_allowed?(:read_user_plan, resource: user, allow_integrations: false, allow_user_via_granular_actor: true),
      :last_modified => calc_last_modified_for_object(user),
      :exclude_email => anonymous_request?,
    )
  end

  # Promote a user to site admin
  put "/user/:user_id/site_admin", operation_id: "enterprise-admin/promote-user-to-be-site-administrator" do
    deliver_error!(404) if GitHub.dotcom_request? || GitHub.global_business&.enterprise_server_scim_enabled?
    set_forbidden_message \
      "You must be an admin to promote another user to an admin."

    user = find_user!

    if current_user == user
      deliver_error! 403,
        message: "Whoa there. You can't revoke your own admin privileges."
    end

    # cap_bypass:to_fix temporary disable - needs to be updated to pass a resource to evaluate CAP https://github.com/github/authorization/issues/2239
    control_access :promote_dotcom_user,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    # login not shown in response therefore safe to use.
    user.grant_site_admin_access("Promoted via API by #{current_user.login}") # rubocop:disable GitHub/DoNotAllowLogin

    deliver_empty status: 204
  end

  # Demote a user from site admin
  delete "/user/:user_id/site_admin", operation_id: "enterprise-admin/demote-site-administrator" do
    deliver_error!(404) if GitHub.dotcom_request? || GitHub.global_business&.enterprise_server_scim_enabled?

    set_forbidden_message \
      "You must be an admin to revoke a user's admin privileges."

    user = find_user!

    if current_user == user
      deliver_error! 403,
        message: "Whoa there. You can't revoke your own admin privileges."
    end

    # cap_bypass:to_fix temporary disable - needs to be updated to pass a resource to evaluate CAP https://github.com/github/authorization/issues/2239
    control_access :demote_site_admin,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    # login not shown in response therefore safe to use.
    user.revoke_privileged_access("Demoted via API by #{current_user.login}") # rubocop:disable GitHub/DoNotAllowLogin

    deliver_empty status: 204
  end

  # Suspend a user
  put "/user/:user_id/suspended", operation_id: "enterprise-admin/suspend-user" do
    deliver_error! 404 unless GitHub.enterprise?

    set_forbidden_message "You must be an admin to suspend a user."
    # cap_bypass:to_fix temporary disable - needs to be updated to pass a resource to evaluate CAP https://github.com/github/authorization/issues/2239
    control_access :suspend,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    user = find_user!
    if current_user == user
      deliver_error! 403,
        message: "You can't suspend yourself. " \
          "You'll have to convince another admin to do that for you."
    end

    if user.organization?
      deliver_error! 422,
        message: "Organizations cannot be suspended."
    end

    if user.scim_managed_user?
      deliver_error! 403,
        message: "Account suspension is managed by SCIM. " \
          "Disable the user from your SCIM provider."
    end

    if user.external_account_suspension?
      deliver_error! 403,
        message: "Account suspension is managed by Active Directory. " \
          "Disable the user from your directory."
    end

    data = receive_with_schema("user", "update-legacy")

    if data && data.key?("reason")
      reason = data["reason"]
    else
      # login not shown in response therefore safe to use.
      reason = "Suspended via API by #{current_user.login}" # rubocop:disable GitHub/DoNotAllowLogin
    end

    if user.suspend(reason)
      deliver_empty status: 204
    else
      deliver_error! 403, message: user.errors[:base].to_sentence
    end
  end

  # Unsuspend a user
  delete "/user/:user_id/suspended", operation_id: "enterprise-admin/unsuspend-user" do
    deliver_error! 404 unless GitHub.enterprise?

    set_forbidden_message "You must be an admin to restore a suspended user."
    # cap_bypass:to_fix temporary disable - needs to be updated to pass a resource to evaluate CAP https://github.com/github/authorization/issues/2239
    control_access :unsuspend,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    user = find_user!

    if user.scim_managed_user?
      deliver_error! 403,
        message: "Account suspension is managed by SCIM. " \
          "Enable the user from your SCIM provider."
    end

    if user.external_account_suspension?
      deliver_error! 403,
        message: "Account suspension is managed by Active Directory. " \
          "Disable the user from your directory."
    end

    data = receive_with_schema("user", "delete-legacy")

    if data && data.key?("reason")
      reason = data["reason"]
    else
      # login not shown in response therefore safe to use.
      reason = "Unsuspended via API by #{current_user.login}" # rubocop:disable GitHub/DoNotAllowLogin
    end

    if user.unsuspend(reason)
      deliver_empty status: 204
    else
      deliver_error! 403, message: user.errors[:base].to_sentence
    end
  end

  def resolve_tenant_from_current_user
    return unless current_user
    if current_user.bot?
      fetch_enterprise_managed_business_for(current_user.installation.target)
    else
      fetch_enterprise_managed_business_for(current_user)
    end
  end

  private

  def response_key(user = nil)
    user ||= current_user

    if access_allowed?(:read_user_private, resource: user, allow_integrations: false, allow_user_via_granular_actor: false)
      :private
    else
      :full
    end
  end

  # - If the current_user is a site admin or a staff member, they can view all emu users
  # - If the current_user is an emu user, they can view other emu users belonging to their business
  # - Logged out users can't view any emus
  def reject_emu_users(users)
    # If the current_user is a site admin or a staff member, they can view all emu users
    return users if current_user&.is_a?(User) && (current_user&.has_staff_role? || current_user&.site_admin?)

    current_user_enterprise_managed_business = resolve_tenant_from_current_user
    users.filter do |u|
      next true if !u.is_enterprise_managed? # we can always view non-emu users
      next false unless current_user # if the user is an EMU, logged-out users can't see them
      # if the current user is an EMU, they can only see EMUs from the same business
      current_user_enterprise_managed_business == fetch_enterprise_managed_business_for(u)
    end
  end
end
