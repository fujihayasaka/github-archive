# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/user_test.rb
##

class Api::Runtime::User < Api::Runtime::SdkBase
  get "/runtime/:app/user", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    app = params[:app]

    control_access :runtime_read_user,
      resource: authed_user,
      user: authed_user, # rubocop:disable GitHub/DisallowEgressUserKey
      app: app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    runtime_app = Spark::RuntimeApp.find_by(permanent_name: app)
    deliver_error!(404) unless runtime_app

    is_owner = runtime_app.user == authed_user

    deliver_raw({
      avatarUrl: authed_user.primary_avatar_url,
      email: authed_user.email,
      id: authed_user.id,
      isOwner: is_owner,
      login: authed_user.display_login,
    })
  end
end
