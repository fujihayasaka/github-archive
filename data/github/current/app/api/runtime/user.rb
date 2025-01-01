# typed: true
# frozen_string_literal: true

##
## Tests for this are at: test/integration/api/runtime/user_test.rb
##

class Api::Runtime::User < Api::Runtime::SdkBase
  get "/runtime/:app/user", operation_id: :internal do
    @route_owner = "@github/copilot-workbench"

    # This endpoint is used to get the user information for the current user in the context of a runtime app.

    runtime_app = find_runtime_app!

    control_access :runtime_read_user,
      resource: current_user,
      app: runtime_app,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    is_owner = runtime_app.user == current_user

    deliver_raw({
      avatarUrl: current_user.primary_avatar_url,
      email: current_user.email,
      id: current_user.id,
      isOwner: is_owner,
      login: current_user.display_login,
    })
  end
end
