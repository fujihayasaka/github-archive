# typed: true
# frozen_string_literal: true

require "test_helper"

class UserUserStatusDependencyTest < GitHub::TestCase
  context "#destroy_org_restricted_user_status" do
    test "deletes user status when it's for the given org" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      status = create(:user_status, user: user, organization: org)

      assert_difference "UserStatus.count", -1 do
        user.destroy_org_restricted_user_status(org)
      end

      refute UserStatus.exists?(status.id)
    end

    test "does not delete user status when it's for a different org than given" do
      user = create(:user)
      org = create(:organization)
      org.add_member(user)
      status = create(:user_status, user: user, organization: org)
      other_org = create(:organization)

      assert_no_difference "UserStatus.count" do
        user.destroy_org_restricted_user_status(other_org)
      end

      assert UserStatus.exists?(status.id)
    end

    test "does not delete user status when it's a public status" do
      user = create(:user)
      status = create(:user_status, user: user)
      some_org = create(:organization)

      assert_no_difference "UserStatus.count" do
        user.destroy_org_restricted_user_status(some_org)
      end

      assert UserStatus.exists?(status.id)
    end

    test "does not delete user status when nil is given" do
      user = create(:user)
      status = create(:user_status, user: user)

      assert_no_difference "UserStatus.count" do
        user.destroy_org_restricted_user_status(nil)
      end

      assert UserStatus.exists?(status.id)
    end

    test "no-op when user does not have a status" do
      user = create(:user)

      assert_no_difference "UserStatus.count" do
        user.destroy_org_restricted_user_status(nil)
      end
    end
  end

  context "#async_user_status_when_not_expired" do
    test "returns nil when status is expired" do
      user = create(:user)
      create(:user_status, user: user, expires_at: 5.weeks.ago)

      assert_nil user.async_user_status_when_not_expired.sync
    end

    test "returns status if expired is nil" do
      user = create(:user)
      status = create(:user_status, user: user, expires_at: nil)

      assert_equal status, user.async_user_status_when_not_expired.sync
    end

    test "returns status if expired is in the future" do
      user = create(:user)
      status = create(:user_status, user: user, expires_at: 5.weeks.from_now)

      assert_equal status, user.async_user_status_when_not_expired.sync
    end
  end

  context "asking if the user is busy" do
    test "returns false for no status" do
      user = create(:user)
      viewer = create(:user)
      refute user.busy?(viewer: viewer)
    end

    test "returns false for unrestricted status" do
      user = create(:user)
      viewer = create(:user)
      create(:user_status, user: user, expires_at: nil)
      refute user.busy?(viewer: viewer)
    end

    test "returns false for spammy user", skip_enterprise: true do
      user = create(:spammy_user)
      viewer = create(:user)
      create(:user_status, user: user, limited_availability: true, expires_at: 1.day.from_now)
      refute user.busy?(viewer: viewer)
    end

    test "returns true for limited availability status" do
      user = create(:user)
      viewer = create(:user)
      expires_at = 1.day.from_now
      create(:user_status, user: user, limited_availability: true, expires_at: expires_at)
      assert user.busy?(viewer: viewer)

      Timecop.freeze(expires_at + 1.week) do
        refute user.busy?(viewer: viewer)
      end
    end
  end
end
