# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationProgrammaticAccessGrantRequestTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include ActiveSupport::Testing::TimeHelpers

  fixtures do
    @pat  = create(:user_programmatic_access)
    @user = @pat.owner

    @org = create(:organization)
    @admin = @org.admins.first

    @org.add_member(@user)

    @subject = OrganizationProgrammaticAccessGrantRequest.create(
      target: @org, user_programmatic_access: @pat, actor: @user
    )

    assert_predicate @subject, :persisted?
  end

  context "validations" do
    context "associations" do
      test "requires an organization" do
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

      test "requires the grant to be owned by the org" do
        org = create(:organization, admin: @user)

        grant = make_programmatic_access_grant(
          access: @pat, target: org,
          permissions: { "metadata" => :read }
        )

        @subject.update(grant: grant)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:base], "target mismatch"
      end

      test "requires the programmatic access to be owned by the same user" do
        rando = create(:user)
        @subject.update(actor: rando)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:base], "owner mismatch"
      end

      test "requires that only one request per user access per org" do
        dup_subject = OrganizationProgrammaticAccessGrantRequest.new(
          target: @org, user_programmatic_access: @pat, actor: @user
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
        subject: @user.resources.plan,
        action: :read,
      )

      assert_difference -> { Permission.count }, -1 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { @subject.destroy }
      end
    end
  end

  context "#approvable_by?" do
    test "returns true if the grant target is adminable by the actor" do
      assert @subject.approvable_by?(@admin)
    end

    test "returns true if the org has opted into auto approving requests" do
      @org.enable_auto_pat_request_approval(actor: @admin)

      assert_predicate @org, :pat_requests_auto_approved?
      assert @subject.approvable_by?(@member)
    end

    context "for org members" do
      test "returns false when asking for the first time" do
        refute_predicate @org, :pat_requests_auto_approved?
        assert_nil @subject.grant

        refute @subject.approvable_by?(@member)
      end

      test "returns false when asking for additional access" do
        member = create(:user)
        member_pat = create(:user_programmatic_access, owner: member)

        @org.add_member(member)

        grant_request = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :read },
        })

        assert_predicate grant_request, :persisted?

        grant = ProgrammaticAccessGrantRequest.approve(grant_request, @admin, entry_point: :test_case)
        assert_predicate grant, :persisted?

        # Make another request with more permissions
        grant_request2 = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :write },
        })

        refute grant_request2.approvable_by?(member)
      end

      test "returns true when asking for the same access" do
        member = create(:user)
        member_pat = create(:user_programmatic_access, owner: member)

        @org.add_member(member)

        grant_request = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :read },
        })

        assert_predicate grant_request, :persisted?

        grant = ProgrammaticAccessGrantRequest.approve(grant_request, @admin, entry_point: :test_case)
        assert_predicate grant, :persisted?

        # Make another request with more permissions
        grant_request2 = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :read },
        })

        assert grant_request2.approvable_by?(member)
      end

      test "returns true when asking for less access" do
        member = create(:user)
        member_pat = create(:user_programmatic_access, owner: member)

        @org.add_member(member)

        grant_request = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :write },
        })

        assert_predicate grant_request, :persisted?

        grant = ProgrammaticAccessGrantRequest.approve(grant_request, @admin, entry_point: :test_case)
        assert_predicate grant, :persisted?

        # Make another request with more permissions
        grant_request2 = ProgrammaticAccessGrantRequest.create({
          access: member_pat, target: @org, actor: member,
          permissions: { "members" => :read },
        })

        assert grant_request2.approvable_by?(member)
      end
    end
  end

  test "instrument request creation" do
    events = subscribe "personal_access_token.request_created"

    user = create(:user)
    @org.add_member(user)
    pat = create(:user_programmatic_access, owner: user)
    org_repo = create(:repository, :minimal, owner: @org)
    request = ProgrammaticAccessGrantRequest.create(
      access: pat,
      actor: user,
      permissions: { "metadata" => :read },
      repositories: [org_repo],
      repository_selection: :subset,
      target: @org,
    )

    expected_payload = {
      user_programmatic_access_id: pat.id,
      user_programmatic_access_name: pat.name,
      user_programmatic_access_request_id: request.id,
      organization_programmatic_access_grant_id: nil,
      requester: user.login,
      requester_id: user.id,
      target: @org.login,
      target_id: @org.id,
      org: @org.login,
      org_id: @org.id,
      repository_selection: "subset",
      repositories: [org_repo.id],
      permissions_added: { "metadata" => "read" },
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
        organization_programmatic_access_grant_id: nil,
        requester: @user.login,
        requester_id: @user.id,
        target: @org.login,
        target_id: @org.id,
        org: @org.login,
        org_id: @org.id,
        repository_selection: "none",
        permissions_added: {},
        permissions_upgraded: {},
        permissions_unchanged: {},
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
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
        organization_programmatic_access_grant_id: nil,
        requester: @user.login,
        requester_id: @user.id,
        target: @org.login,
        target_id: @org.id,
        org: @subject.target.name,
        org_id: @subject.organization_id,
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

  context "#deny!" do
    test "instruments the denied request" do
      events = subscribe "personal_access_token.request_denied"
      @subject.deny!(reason: "Cause I said so")

      expected_payload = {
        user_programmatic_access_id: @pat.id,
        user_programmatic_access_name: @pat.name,
        user_programmatic_access_request_id: @subject.id,
        organization_programmatic_access_grant_id: nil,
        requester: @user.login,
        requester_id: @user.id,
        target: @org.login,
        target_id: @org.id,
        org: @org.login,
        org_id: @org.id,
        repository_selection: "none",
        permissions_added: {},
        permissions_upgraded: {},
        permissions_unchanged: {},
        reason: "Cause I said so",
      }

      assert event = events.pop, "an event was expected"
      assert_same_hash expected_payload, event.payload
    end
  end

  test "#target_for_conditonal_access aliases to the target" do
    assert_equal @org, @subject.target_for_conditional_access
  end

  context "#generate_webhook_payload" do
    context "when the request does not include any repositories" do
      test "it initializes an event with expected attributes" do
        user = create(:user)
        @org.add_member(user)
        pat = create(:user_programmatic_access, owner: user)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          repositories: [],
          repository_selection: :none,
          target: @org,
        )
        freeze_time do
          # The expected attributes won't include 'repositories' since 'repository_selection' is :none.
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: {},
            permissions_unchanged: {},
            permissions_upgraded: {}
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(equals(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: {},
            permissions_unchanged: {},
            permissions_upgraded: {}
          )).returns(event).once
          request.generate_webhook_payload(action: :created, current_actor: user, token_expires_at: Time.now)
        end
      end
    end

    context "when the request is for all of repositories" do
      test "it initializes an event with expected attributes" do
        user = create(:user)
        @org.add_member(user)
        pat = create(:user_programmatic_access, owner: user)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          repositories: @org.repositories,
          repository_selection: :all,
          target: @org,
        )
        freeze_time do
          # To reduce the size of payload,
          # the expected attributes won't include 'repositories' since 'repository_selection' is :all.
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {}
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {}
          ).returns(event).once

          request.generate_webhook_payload(action: :created, current_actor: user, token_expires_at: Time.now)
        end
      end
    end

    context "when the request is for a subset of repositories" do
      test "it initializes an event with expected attributes" do
        user = create(:user)
        @org.add_member(user)
        pat = create(:user_programmatic_access, owner: user)
        org_repo = create(:repository, :minimal, owner: @org)
        request = ProgrammaticAccessGrantRequest.create(
          access: pat,
          actor: user,
          permissions: { "metadata" => :read },
          repositories: [org_repo],
          repository_selection: :subset,
          target: @org,
        )
        freeze_time do
          event = Hook::Event::PersonalAccessTokenRequestEvent.new(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
            token_expires_at: Time.now.utc.iso8601,
            triggered_at: Time.now,
            permissions_added: { "metadata" => "read" },
            permissions_unchanged: {},
            permissions_upgraded: {},
            repositories: [org_repo.id]
          )

          Hook::Event::PersonalAccessTokenRequestEvent.expects(:new).with(
            action: :created,
            actor_id: user.id,
            user_programmatic_access_id: pat.id,
            target_id: @org.id,
            target_type: @org.class.name,
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
