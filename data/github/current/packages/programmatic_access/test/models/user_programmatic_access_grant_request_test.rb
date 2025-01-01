# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProgrammaticAccessGrantRequestTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  fixtures do
    @pat  = create(:user_programmatic_access)
    @user = @pat.owner
    @other_user = create(:user)

    @subject = UserProgrammaticAccessGrantRequest.create(
      target: @other_user, user_programmatic_access: @pat, actor: @user
    )

    assert_predicate @subject, :persisted?
  end

  context "validations" do
    context "associations" do
      test "requires a target" do
        @subject.update(target: nil)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:target], "must exist"
      end

      test "requires a user programmatic access" do
        @subject.update(user_programmatic_access: nil)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:user_programmatic_access], "must exist"
      end

      test "requires an actor" do
        @subject.update(actor: nil)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:actor], "must exist"
      end

      test "requires an associated grant to be owned by the target" do
        grant = UserProgrammaticAccessGrant.create(
          target: @user, user_programmatic_access: @pat
        )

        @subject.update(grant: grant)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:base], "target mismatch"
      end

      test "requires that only one request per access per target" do
        dup_subject = UserProgrammaticAccessGrantRequest.new(
          target: @other_user, user_programmatic_access: @pat, actor: @user
        )

        refute_predicate dup_subject, :valid?
        assert_includes dup_subject.errors[:user_programmatic_access_id], "has already been taken"
      end
    end

    context "reason" do
      test "can be nil" do
        assert_nil @subject.reason
        assert_predicate @subject, :valid?
      end

      test "must meet a minimum length of 1 if provided" do
        @subject.update(reason: "")

        refute_predicate @subject, :valid?
        assert_equal "is too short (minimum is 1 character)", @subject.errors[:reason].to_sentence
      end

      test "cannot be more than 1024 characters" do
        @subject.update(reason: ("a" * 1025))

        refute_predicate @subject, :valid?
        assert_equal "is too long (maximum is 1024 characters)", @subject.errors[:reason].to_sentence
      end

      test "can contain emoji" do
        @subject.update(reason: "I really enjoy 🍰")
        assert_predicate @subject, :valid?
      end
    end
  end

  context "callbacks" do
    test "destroys permissions in the background" do
      Permissions::Service.grant_app_permission(
        actor: @subject,
        subject: @other_user.resources.plan,
        action: :read
      )

      assert_difference -> { Permission.count }, -1 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @subject.destroy }
      end
    end
  end

  context "#approvable_by?" do
    test "returns true if the grant target is the actor" do
      assert @subject.approvable_by?(@subject.target)
    end

    test "returns false if the grant target is not the actor" do
      refute @subject.approvable_by?(create(:user))
    end
  end

  test "instrument request creation" do
    events = subscribe "personal_access_token.request_created"

    user = create(:user)
    pat = create(:user_programmatic_access, owner: user)

    request = ProgrammaticAccessGrantRequest.create(
      access: pat,
      actor: user,
      permissions: { "plan" => :read },
      target: user,
    )

    expected_payload = {
      user_programmatic_access_id: pat.id,
      user_programmatic_access_name: pat.name,
      user_programmatic_access_request_id: request.id,
      user_programmatic_access_grant_id: nil,
      requester: user.login,
      requester_id: user.id,
      target: user.login,
      target_id: user.id,
      user: user.login,
      user_id: user.id,
      repository_selection: "none",
      permissions_added: { "plan" => "read" },
      permissions_upgraded: {},
      permissions_unchanged: {},
    }

    assert event = events.pop, "an event was expected"
    assert_same_hash expected_payload, event.payload
  end

  context "#cancel" do
    test "instruments a successful cancellation" do
      events = subscribe "personal_access_token.request_cancelled"
      @subject.cancel

      expected_payload = {
        user_programmatic_access_id: @pat.id,
        user_programmatic_access_name: @pat.name,
        user_programmatic_access_request_id: @subject.id,
        user_programmatic_access_grant_id: nil,
        requester: @user.login,
        requester_id: @user.id,
        target: @other_user.login,
        target_id: @other_user.id,
        user: @subject.target.login,
        user_id: @subject.target.id,
        repository_selection: "none",
        permissions_added: {},
        permissions_upgraded: {},
        permissions_unchanged: {},
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end

    test "includes repositories in the payload if the request is for a subset" do
      repo = create(:repository, :minimal, owner: @subject.target)
      _other_repo = create(:repository, :minimal, owner: @subject.target)

      Permissions::Service.grant_app_permission(actor: @subject, subject: repo.resources.metadata, action: :read)

      events = subscribe "personal_access_token.request_cancelled"
      @subject.cancel

      expected_payload = {
        user_programmatic_access_id: @pat.id,
        user_programmatic_access_name: @pat.name,
        user_programmatic_access_request_id: @subject.id,
        user_programmatic_access_grant_id: nil,
        requester: @user.login,
        requester_id: @user.id,
        target: @other_user.login,
        target_id: @other_user.id,
        user: @subject.target.name,
        user_id: @subject.target.id,
        repository_selection: "subset",
        repositories: [repo.id],
        permissions_added: { "metadata" => "read" },
        permissions_upgraded: {},
        permissions_unchanged: {},
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  test "#target_for_conditonal_access aliases to the target" do
    assert_equal @other_user, @subject.target_for_conditional_access
  end

  context "#generate_webhook_payload" do
    context "when the request does not include any repositories" do
      test "it initializes an event with expected attributes" do
        user = create(:user)
        pat = create(:user_programmatic_access, owner: user)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          target: user,
          repositories: [],
          repository_selection: :none,
        )
        freeze_time do
          # The expected attributes won't include 'repositories' since 'repository_selection' is :none.
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: {},
            permissions_unchanged: {},
            permissions_upgraded: {},
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: {},
            permissions_unchanged: {},
            permissions_upgraded: {},
          ).returns(event).once

          request.generate_webhook_payload(action: :created, current_actor: user, token_expires_at: Time.now)
        end
      end
    end

    context "when the request is for all of repositories" do
      test "it initializes an event with expected attributes" do
        user = create(:user)
        pat = create(:user_programmatic_access, owner: user)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          target: user,
          repositories: [create(:repository, :minimal, owner: user)],
          repository_selection: :all,
        )
        freeze_time do
          # To reduce the size of payload,
          # the expected attributes won't include 'repositories' since 'repository_selection' is :all.
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {},
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {},
          ).returns(event).once

          request.generate_webhook_payload(action: :created, current_actor: user, token_expires_at: Time.now)
        end
      end
    end

    context "when the request is for a subset of repositories" do
      test "it initializes an with expected attributes" do
        user = create(:user)
        pat = create(:user_programmatic_access, owner: user)
        user_repo = create(:repository, :minimal, owner: user)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          target: user,
          repositories: [user_repo],
          repository_selection: :subset,
        )
        freeze_time do
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {},
            repositories: [user_repo.id]
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: user.id,
            target_type: user.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {},
          ).returns(event).once

          request.generate_webhook_payload(action: :created, current_actor: user, token_expires_at: Time.now)
        end
      end
    end

    test "it generates a webhook payload" do
      delivery_system_mock = Minitest::Mock.new(Hook::DeliverySystem)
      delivery_system_mock.expects(:generate_hookshot_payloads)
      Hook::DeliverySystem.expects(:new).returns(delivery_system_mock).once
      @subject.generate_webhook_payload(action: :created, current_actor: @user)
    end
  end

  context "#queue_webhook_delivery" do
    test "it queues a webhook delivery" do
      delivery_system_mock = Minitest::Mock.new(Hook::DeliverySystem)
      delivery_system_mock.expects(:deliver_later)
      @subject.instance_variable_set(:@delivery_system, delivery_system_mock)
      @subject.queue_webhook_delivery
    end
  end
end
