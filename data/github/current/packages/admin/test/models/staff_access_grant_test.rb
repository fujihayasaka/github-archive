# typed: true
# frozen_string_literal: true

require "test_helper"

class StaffAccessGrantTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:user, login: "user", plan: "medium")
    @repo = create(:private_repository, :minimal, name: "repo", owner: @repo_owner)
    @staffer = create(:staff_admin_user, login: "staffer")
    @reason = "UI bugs"
    @grant = StaffAccessGrant.create(granted_by: @repo_owner, accessible: @repo, reason: @reason)
  end

  context "creation and validation" do
    test "can be created" do
      assert @grant.valid?
    end

    test "requires granted_by" do
      assert_raises ActiveRecord::RecordInvalid do
        @grant.update!(granted_by: nil)
      end
    end

    test "requires reason" do
      assert_raises ActiveRecord::RecordInvalid do
        @grant.update!(reason: nil)
      end
    end

    test "requires accessible" do
      assert_raises ActiveRecord::RecordInvalid do
        @grant.update!(accessible: nil)
      end
    end

    test "requires expires_at" do
      assert_raises ActiveRecord::RecordInvalid do
        @grant.update!(expires_at: nil)
      end
    end

    test "calculates expires_at" do
      refute_nil @grant.expires_at
    end

    test "expire date cannot be before created_at" do
      assert_raises ActiveRecord::RecordInvalid do
        @grant.update!(expires_at: Time.now - 1.day)
      end
    end

    test "creates an audit log entry on create" do
      request = StaffAccessRequest.create(requested_by: @staffer, accessible: @repo, reason: @reason)

      events = subscribe "staff_access_grant.create"
      expected_payload = {
        actor:                   @repo_owner.login,
        actor_id:                @repo_owner.id,
        repo:                    @repo.name_with_owner,
        repo_id:                 @repo.id,
        public_repo:             @repo.public?,
        reason:                  @reason,
        staff_access_request_id: request.id,
      }

      StaffAccessGrant.create(granted_by: @repo_owner, accessible: @repo, reason: @reason, request: request)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#revoke" do
    test "sets revoked_at" do
      now = Time.now

      Timecop.freeze(now) do
        @grant.revoke(@repo_owner)
        assert_equal now.to_i, @grant.reload.revoked_at.to_i
      end
    end

    test "sets revoked_by" do
      @grant.revoke(@repo_owner)

      assert_equal @repo_owner, @grant.reload.revoked_by
    end

    test "revoking_user must be an admin of the accessible" do
      some_other_user = create(:user)

      assert_raises StaffAccessGrant::InsufficientAbilities do
        @grant.revoke(some_other_user)
      end
    end

    test "raises an error if not active" do
      @grant.revoke(@repo_owner)

      assert_raises StaffAccessGrant::GrantNotActive do
        @grant.reload.revoke(@repo_owner)
      end
    end

    test "creates an audit log entry" do
      request = StaffAccessRequest.create(requested_by: @staffer, accessible: @repo, reason: @reason)

      events = subscribe "staff_access_grant.revoke"
      expected_payload = {
        actor:                   @repo_owner.login,
        actor_id:                @repo_owner.id,
        repo:                    @repo.name_with_owner,
        repo_id:                 @repo.id,
        public_repo:             @repo.public?,
        reason:                  @reason,
        staff_access_request_id: request.id,
      }

      @grant.update!(request: request)
      @grant.revoke(@repo_owner)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end unless GitHub.enterprise?
