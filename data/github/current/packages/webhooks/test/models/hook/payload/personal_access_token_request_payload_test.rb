# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadPersonalAccessTokenRequestPayloadTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include AuthndClientTestHelpers


  fixtures do
    @org = create(:organization)
    @owner = create(:user)
    @org.add_member(@owner)
    @repo = create(:repository, owner: @org)

    @pat = make_user_programmatic_access_with_grant_request(
      target: @org,
      actor: @owner,
      permissions: { "actions" => "write", "metadata" => "read", "organization_administration" => "read" },
      repository_selection: :subset,
      repositories: [@repo]
    )

    @pat_request = @pat.grant_request

    @github_app   = create(:integration, :with_active_hook, :with_personal_access_token_request_event)
    @installation = make_integration_installation(integration: @github_app, repository: @repo)
  end

  setup do
    setup_authnd_stub
  end

  teardown do
    remove_authnd_stub
  end

  def create_event(action: :created, actor: @owner, user_programmatic_access: @pat, target: @org)
    Hook::Event::PersonalAccessTokenRequestEvent.new action: action,
      actor_id: actor.id,
      user_programmatic_access_id: user_programmatic_access.id,
      target_id: target.id,
      target_type: target.class.name,
      permissions_added: { "organization_administration" => "read" },
      permissions_upgraded: { "actions" => "write" },
      permissions_unchanged: { "metadata" => "read" },
      repositories: [@repo.id]
  end

  context "organization" do
    [:created, :approved, :denied, :cancelled].each do |action|
      test action.to_s do
        expected_expiration = 30.days.from_now.utc
        stub_authnd_programmatic_access_find_credentials(expires_at_utc: expected_expiration)

        event = create_event action: action
        payload = Hook::Payload::PersonalAccessTokenRequestPayload.new(event).to_hash

        assert_equal action, payload[:action]

        access = @pat_request.user_programmatic_access
        assert_equal @pat_request.id, payload[:personal_access_token_request][:id]
        assert_equal @owner.id, payload[:personal_access_token_request][:owner][:id]

        expected_permissions_added = { organization: { "organization_administration" => "read" } }
        assert_equal expected_permissions_added, payload[:personal_access_token_request][:permissions_added]

        expected_permissions_upgraded = { repository: { "actions" => "write" } }
        assert_equal expected_permissions_upgraded, payload[:personal_access_token_request][:permissions_upgraded]

        expected_permissions_result = { repository: { "metadata" => "read", "actions" => "write" }, organization: { "organization_administration" => "read" } }
        assert_equal expected_permissions_result, payload[:personal_access_token_request][:permissions_result]

        assert_equal "subset", payload[:personal_access_token_request][:repository_selection]
        assert_equal 1, payload[:personal_access_token_request][:repository_count]
        assert_equal [@repo.id], payload[:personal_access_token_request][:repositories].map { |r| r[:id] }
        assert_equal @pat_request.created_at.iso8601, payload[:personal_access_token_request][:created_at]
        assert_equal false, payload[:personal_access_token_request][:token_expired]
        assert_equal expected_expiration.iso8601, payload[:personal_access_token_request][:token_expires_at]
        assert_nil payload[:personal_access_token_request][:token_last_used_at]
      end
    end
  end
end
