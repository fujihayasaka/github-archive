# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPersonalAccessTokenRequestEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @pat = create(:user_programmatic_access)
    @owner = @pat.owner
    @org = create(:organization)
    @org.add_member(@owner)

    @pat_request = OrganizationProgrammaticAccessGrantRequest.create(
      target: @org, user_programmatic_access: @pat, actor: @owner
    )

    @github_app   = create(:integration, :with_active_hook, :with_personal_access_token_request_event)
    @installation = make_integration_installation(integration: @github_app, repository: create(:repository, owner: @org))
  end

  def create_event(
    action: :created,
    actor: @owner,
    user_programmatic_access: @pat,
    target: @org,
    permissions_added: { "packages" => "read" },
    permissions_upgraded: { "organization_secrets" => "write" },
    permissions_unchanged: { "metadata" => "read" },
    token_expires_at: nil
  )
    Hook::Event::PersonalAccessTokenRequestEvent.new action: action,
      actor_id: actor.id,
      user_programmatic_access_id: user_programmatic_access.id,
      target_id: target.id,
      target_type: target.class.name,
      permissions_added: permissions_added,
      permissions_upgraded: permissions_upgraded,
      permissions_unchanged: permissions_unchanged,
      token_expires_at: token_expires_at
  end

  test "attributes required" do
    assert_event_required_attributes Hook::Event::PersonalAccessTokenRequestEvent,
    :action,
    :actor_id,
    :user_programmatic_access_id,
    :target_id,
    :target_type
  end

  test "attributes not required" do
    refute_event_required_attributes Hook::Event::PersonalAccessTokenRequestEvent,
      :token_expires_at,
      :repositories,
      :permissions_added,
      :permissions_upgraded,
      :permissions_unchanged
  end

  context "#target_organization" do
    test "is looked up using the target_id" do
      event = create_event

      assert_equal @org, event.target_organization
    end

    test "is not looked up if the target_type is not an Organization" do
      event = create_event target: @owner

      assert_nil event.target_organization
    end
  end

  context "#actor" do
    test "is looked up using the actor_id" do
      event = create_event

      assert_equal @owner, event.actor
    end
  end

  context "#requester" do
    test "is looked up using the actor that created the PAT request" do
      event = create_event

      assert_equal @pat_request.actor, event.requester
    end
  end

  context "#subscribed_hooks" do
    test "returns the installation hook for the integration" do
      event = create_event

      assert_equal [@github_app.hook], event.subscribed_hooks
    end

    test "returns [] if the integration does not have a hook" do
      @github_app.hook.destroy

      event = create_event

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the integration hook is not active" do
      @github_app.hook.update(active: false)
      @github_app.hook.reload

      refute_predicate @github_app.hook, :active?

      event = create_event

      assert_empty event.subscribed_hooks
    end

    test "returns [] if the target_type is Repository" do
      event = create_event target: create(:repository, :minimal, owner: @org)

      assert_equal [], event.subscribed_hooks
    end
  end

  context "#personal_access_token_request" do
    test "returns expected org PAT request" do
      event = create_event

      assert_equal @pat_request, event.personal_access_token_request
    end

    test "returns expected user PAT request" do
      user_pat = create(:user_programmatic_access)
      user_pat_request = UserProgrammaticAccessGrantRequest.create(
        target: @owner,
        user_programmatic_access: user_pat,
        actor: user_pat.owner
      )
      event = create_event user_programmatic_access: user_pat, target: @owner

      assert_nil event.personal_access_token_request
    end
  end

  context "#permissions_result" do
    test "returns expected permissions result" do
      attrs = {
        permissions_added: { "packages" => "read" },
        permissions_upgraded: { "organization_secrets" => "write" },
        permissions_unchanged: { "metadata" => "read" }
      }
      event = create_event **attrs

      expected_permissions_result = {}.merge(
        **attrs[:permissions_added],
        **attrs[:permissions_upgraded],
        **attrs[:permissions_unchanged]
      )
      assert_equal expected_permissions_result, event.permissions_result
    end
  end

  context "#token_expired" do
    test "returns true if token expired" do
      event = create_event token_expires_at: 1.day.ago.utc.iso8601

      assert_predicate event, :token_expired?
    end

    test "returns false if token has not expired" do
      event = create_event token_expires_at: 1.day.from_now.utc.iso8601

      refute event.token_expired?
    end

    test "returns nil if no token expiry date is provided" do
      event = create_event token_expires_at: nil

      refute_predicate event, :token_expired?
    end
  end

  context "#deliverable?" do
    test "returns true if the PAT request requires approval" do
      assert_predicate create_event, :deliverable?
    end

    test "returns false if the PAT request does not require approval" do
      event = create_event action: :created
      event.stub(:personal_access_token_request, @pat_request) do
        @pat_request.stub(:approvable_by?, true) do
          refute_predicate event, :deliverable?
        end
      end
    end

    test "returns false if the target_type is not 'Organization'" do
      event = create_event target: @owner

      refute_predicate event, :deliverable?
    end
  end
end
