# typed: true
# frozen_string_literal: true

require "test_helper"

class StaffAccessRequestTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:user, login: "user", plan: "medium")
    @staffer = create(:staff_admin_user, login: "staffer")
    @non_staff_user = create(:user)
    @repo     = create(:private_repository, :minimal, name: "repo", owner: @repo_owner)
    @reason   = "UI bugs"
    @request = StaffAccessRequest.create(requested_by: @staffer, accessible: @repo, reason: @reason)
  end

  context "validations" do
    test "can be created" do
      assert @request.valid?
    end

    test "requires requested_by" do
      assert_raises ActiveRecord::RecordInvalid do
        @request.update!(requested_by: nil)
      end
    end

    test "requires an accessible" do
      assert_raises ActiveRecord::RecordInvalid do
        @request.update!(accessible: nil)
      end
    end

    test "requires expires_at" do
      assert_raises ActiveRecord::RecordInvalid do
        @request.update!(expires_at: nil)
      end
    end

    test "requires a reason" do
      assert_raises ActiveRecord::RecordInvalid do
        @request.update!(reason: nil)
      end
    end

    test "calculates expires_at" do
      refute_nil @request.expires_at
    end

    test "expire date cannot be before created_at" do
      assert_raises ActiveRecord::RecordInvalid do
        @request.update!(expires_at: Time.now - 1.day)
      end
    end

    test "requested_by must be staff on creation" do
      assert_raises ActiveRecord::RecordInvalid do
        StaffAccessRequest.create! \
          requested_by: @non_staff_user,
          accessible: @repo,
          reason: @reason
      end
    end

    test "does not require requested_by to be staff on update" do
      @staffer.revoke_privileged_access "Reasons"
      refute_predicate @staffer, :site_admin?

      assert_predicate @request.reload, :valid?
      refute_predicate @request.requested_by, :site_admin?
    end

    test "creates an audit log entry on create" do
      events = subscribe "staff_access_request.create"
      expected_payload = {
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        reason: @reason,
      }

      StaffAccessRequest.create(requested_by: @staffer, accessible: @repo, reason: @reason)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#accept" do
    test "creates a StaffAccessGrant" do
      grant = @request.accept(@repo_owner)

      refute_nil grant
    end

    test "makes request inactive" do
      @request.accept(@repo_owner)
      refute @request.reload.active?
    end

    test "works when requested_by is no longer a site admin" do
      @staffer.revoke_privileged_access "Reasons"
      refute_predicate @staffer, :site_admin?

      assert grant = @request.accept(@repo_owner)
    end

    test "raises an error if the request is inactive" do
      @request.cancel(@staffer)

      assert_raises StaffAccessRequest::RequestNotActive do
        @request.accept(@repo_owner)
      end
    end

    test "raises an error if the accessible is unadminable by the user" do
      assert_raises StaffAccessRequest::InsufficientAbilities do
        @request.accept(@non_staff_user)
      end
    end

    test "creates an audit log entry" do
      events = subscribe "staff_access_request.accept"
      expected_payload = {
        actor: @repo_owner.login,
        actor_id: @repo_owner.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        reason: @reason,
      }

      @request.accept(@repo_owner)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#cancel" do
    test "sets cancelled_at" do
      now = Time.now

      Timecop.freeze(now) do
        @request.cancel(@staffer)
        assert_equal now.to_i, @request.reload.cancelled_at.to_i
      end
    end

    test "sets cancelled_by" do
      @request.cancel(@staffer)
      assert_equal @staffer, @request.reload.cancelled_by
    end

    test "cancelling_user must be staff" do
      assert_raises StaffAccessRequest::InsufficientAbilities do
        @request.cancel(@non_staff_user)
      end
    end

    test "works when requested_by is no longer a site admin" do
      @staffer.revoke_privileged_access "Reasons"
      refute_predicate @staffer, :site_admin?
      other_staffer = create :staff_admin_user, login: "other-staffer"
      assert_predicate other_staffer, :site_admin?

      @request.cancel(other_staffer)

      assert_equal other_staffer, @request.reload.cancelled_by
    end

    test "raises an error if not active" do
      @request.cancel(@staffer)

      assert_raises StaffAccessRequest::RequestNotActive do
        @request.reload.cancel(@staffer)
      end
    end

    test "creates an audit log entry" do
      events = subscribe "staff_access_request.cancel"
      expected_payload = {
        staff_actor: @staffer.login,
        staff_actor_id: @staffer.id,
        actor: User.staff_user.login,
        actor_id: User.staff_user.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        reason: @reason,
      }

      @request.cancel(@staffer)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "#deny" do
    test "sets denied_at" do
      now = Time.now

      Timecop.freeze(now) do
        @request.deny(@repo_owner)
        assert_equal now.to_i, @request.reload.denied_at.to_i
      end
    end

    test "sets denied_by" do
      @request.deny(@repo_owner)
      assert_equal @repo_owner, @request.reload.denied_by
    end

    test "works when requested_by is no longer a site admin" do
      @staffer.revoke_privileged_access "Reasons"
      refute_predicate @staffer, :site_admin?

      @request.deny(@repo_owner)
      assert_equal @repo_owner, @request.reload.denied_by
    end

    test "denying_user must be an admin of the accessible" do
      assert_raises StaffAccessRequest::InsufficientAbilities do
        @request.deny(@non_staff_user)
      end
    end

    test "raises an error if not active" do
      @request.cancel(@staffer)

      assert_raises StaffAccessRequest::RequestNotActive do
        @request.reload.deny(@repo_owner)
      end
    end

    test "creates an audit log entry" do
      events = subscribe "staff_access_request.deny"
      expected_payload = {
        actor: @repo_owner.login,
        actor_id: @repo_owner.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        reason: @reason,
      }

      @request.deny(@repo_owner)

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end unless GitHub.enterprise?
