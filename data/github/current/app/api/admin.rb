# typed: true
# frozen_string_literal: true

class Api::Admin < Api::App

  before do
    @accepted_scopes = :site_admin if GitHub.require_site_admin_scope?
    # Child classes should add control_access calls to their routes, with an appropriate resource set for CAP
    control_access :admin_api, challenge: true, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed
  end
end
