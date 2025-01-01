# typed: true
# frozen_string_literal: true

class Api::Mobile::Support < Api::App
  # Create a SignedAuthToken to authenticate submission of a support request
  post "/mobile/support-token", operation_id: :internal do
    @route_owner = "@github/pe-mobile"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    control_access :mobile_support_token, resource: current_user, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false

    # only GitHub Mobile apps can create a MobileSupportToken
    if Apps::Internal.capable?(:mobile_support_token, app: current_user.oauth_access.application)
      token = current_user.signed_auth_token(scope: "MobileSupportToken", expires: 8.hours.from_now, data: { app_id: current_user.oauth_access.application_id })
      deliver_raw({ token: token })
    else
      deliver_error(404)
    end
  end

  # Validates a SupportToken SignedAuthToken. Returns user ID and oauth app ID that created the token.
  # Used by support.github.com to identify the user creating the support ticket.
  get "/mobile/support-token", operation_id: :internal do # rubocop:todo GitHub/ControlAccess
    @route_owner = "@github/pe-mobile"
    deliver_error! 404, message: "Not enabled for Enterprise" if GitHub.enterprise?

    if token = Api::RequestCredentials.token_from_scheme(env, "remoteauth")
      verified_token = User.verify_signed_auth_token(token: token, scope: "MobileSupportToken")
      if verified_token.valid?
        deliver_raw({
          user_id: verified_token.user.id,
          app_id: verified_token.data["app_id"]
        })
      else
        deliver_error(404)
      end
    else
      deliver_error(404)
    end
  end
end
