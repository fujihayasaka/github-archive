# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadGitHubAppAuthorizationPayloadTest < GitHub::TestCase
  fixtures do
    @authorized_user = create(:user, login: "authorized-user")
    @github_app      = create(:integration)
  end

  test "v3" do
    event = Hook::Event::GitHubAppAuthorizationEvent.new(
      action: :revoked,
      actor_id: @authorized_user.id,
      integration_id: @github_app.id,
    )

    payload = Hook::Payload::GitHubAppAuthorizationPayload.new(event)

    v3 = payload.to_hash

    assert_equal :revoked, v3[:action]

    assert_equal @authorized_user.login, v3[:sender][:login]
  end
end
