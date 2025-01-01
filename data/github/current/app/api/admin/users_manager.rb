# typed: true
# frozen_string_literal: true

class Api::Admin::UsersManager < Api::Admin
  include BusinessesHelper

  before do
    deliver_error!(404) unless GitHub.enterprise_only_api_enabled?
  end

  # Create user. The provided login should match what the auth mechanism provides.
  post "/admin/users", operation_id: "enterprise-admin/create-user" do # rubocop:todo GitHub/ControlAccess
    # Only prevents user creation when SCIM is enabled without builtin auth
    if scim_managed_enterprise?(GitHub.global_business) && !GitHub.auth.builtin_auth_fallback?
      deliver_error! 404,
        message: "Account creation is managed through the IdP."
    end

    data = receive(Hash)

    user = User.new_with_random_password(data["login"])

    user.email = data["email"]

    if user.valid?
      user.save
      if data["suspended"] == true
        user.suspend("Suspended on create")
      end
      deliver :user_hash, user, status: 201
    else
      deliver_error 422, errors: user.errors
    end
  end

  # Create or reset a GitHub site administrator 'impersonation' token
  # rubocop:todo GitHub/ControlAccess
  post "/admin/user/:user_id/authorizations", operation_id: "enterprise-admin/create-impersonation-o-auth-token" do
    data = receive_with_schema("impersonation-token", "create")

    user = find_user!
    deliver_error!(404) if user.ghost?

    app = OauthApplication.find_by id: GitHub.enterprise_admin_oauth_app_id
    deliver_error!(404) unless app
    accesses = user.oauth_accesses

    if access = accesses.find_by(application: app)
      access.set_scopes(data["scopes"].reject { |e| e == "site_admin" })
      deliver :oauth_access_hash, access, status: 200, token: access.reset_token
    else
      access = user.oauth_accesses.build(
        application: app,
        scopes: Array(data["scopes"].reject { |e| e == "site_admin" }))
      token = access.set_random_token_pair
      if !(access.valid? && access.save)
        deliver_error 422, errors: access.errors
      else
        deliver :oauth_access_hash, access, status: 201, token: token
      end
    end
  end
  # rubocop:enable GitHub/ControlAccess

  # Delete GitHub site administrator 'impersonation' token for specified user
  # rubocop:todo GitHub/ControlAccess
  delete "/admin/user/:user_id/authorizations", operation_id: "enterprise-admin/delete-impersonation-o-auth-token" do
    app = OauthApplication.find_by id: GitHub.enterprise_admin_oauth_app_id
    deliver_error!(404) unless app

    user = find_user!
    accesses = user.oauth_accesses
    access = accesses.find_by(application: app)
    deliver_error!(404) unless access
    access.delete if access
    deliver_empty status: 204
  end
  # rubocop:enable GitHub/ControlAccess

  # Rename a user
  # rubocop:todo GitHub/ControlAccess
  patch "/admin/user/:user_id", operation_id: "enterprise-admin/update-username-for-user" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    rename_user
  end
  # rubocop:enable GitHub/ControlAccess

  # rubocop:todo GitHub/ControlAccess
  post "/admin/user/:user_id", operation_id: :deprecated do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    rename_user
  end
  # rubocop:enable GitHub/ControlAccess

  # Delete a user
  delete "/admin/user/:user_id", operation_id: "enterprise-admin/delete-user" do # rubocop:todo GitHub/ControlAccess
    user = find_user!

    if user.managed_user_deletion_disabled?
      deliver_error! 404, message: "Account deletion is managed through the IdP."
    end

    deliver_error!(404) if user.ghost?
    if current_user == user
      deliver_error! 403,
        message: "You can't delete yourself. " \
          "You'll have to convince another admin to do that for you."
    end
    if user.organization?
      # API is only used in GHES therefore safe to use login
      deliver_error! 404,
        message: "#{user.login} is an organization. You can only delete organizations via the site admin dashboard." # rubocop:disable GitHub/DoNotAllowLogin
    end
    # This intentionally doesn't use async_destroy so that all the
    # before_destroy callbacks will be run and stop e.g. the last
    # admin of an organization being deleted.
    unless user.destroy
      deliver_error! 422,
        errors: user.errors
    end

    deliver_empty status: 204
  end

  private

  def rename_user
    if scim_managed_enterprise?(GitHub.global_business)
      deliver_error! 404, \
        message: "Account renaming is managed through the IdP."
    end

    user = find_user!

    if user.organization?
      # API is only used in GHES therefore safe to use login
      deliver_error! 404, \
        message: "#{user.login} is an organization. You can only rename users with this API." # rubocop:disable GitHub/DoNotAllowLogin
    end

    if user.system_account?
      deliver_error! 404, \
        message: "This account cannot be renamed because it is a system account that " \
          "is important for GitHub to function properly."
    end

    data = receive(Hash)
    attributes = attr(data, :login)
    if user.rename(attributes[:login])
      message = "Job queued to rename user. It may take a few minutes to complete."
      url     = api_url("/user/#{user.id}")
      response["location"] = url
      deliver_raw(
        {
         message: message,
         url: url,
        },
        status: 202,
      )
    else
      deliver_error! 422,
        errors: user.errors
    end
  end
end
