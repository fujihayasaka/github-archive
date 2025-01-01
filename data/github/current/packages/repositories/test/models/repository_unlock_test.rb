# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryUnlockTest < GitHub::TestCase
  fixtures do
    create(:global_business)
    @user = create(:user, login: "user", plan: "medium")
    @staff = create(:staff_admin_user, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
    @repo   = create(:private_repository, name: "repo", owner: @user)
    @reason = "Investigating PR issues"
    @staff_grant = create :staff_access_grant, granted_by: @user, accessible: @repo, reason: @reason

    unless GitHub.enterprise?
      @emu_business = create(:business, :enterprise_managed)
      @emu_owner = @emu_business.find_first_emu_owner
      @emu_user = create(:emu, business: @emu_business)
      @emu_owned_repo = create(:repository, owner: @emu_user)
    end
  end

  test "can be created" do
    RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    unlock = RepositoryUnlock.find_by! repository_id:  @repo
    assert_equal unlock.repository, @repo
  end

  test "is also returned when created" do
    unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    assert_equal unlock.repository, @repo
    assert_equal unlock.reason, @reason
  end

  if GitHub.enterprise?
    test "does NOT require a grant" do
      unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason)
      assert unlock.valid?
      assert_nil unlock.staff_access_grant
    end
  else
    test "requires an active grant" do
      @staff_grant.revoke(@user)

      assert_raises ActiveRecord::RecordInvalid do
        RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
      end
    end
  end

  test "is always created with default expiry time" do
    current_time = Time.local(2020, 11, 10)
    expire_time = current_time + RepositoryUnlock::DEFAULT_EXPIRY

    Timecop.freeze(current_time) do
      grant = create :staff_access_grant, granted_by: @user, accessible: @repo, reason: @reason
      unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, grant)

      assert_equal unlock.repository, @repo
      assert_equal unlock.reason, @reason
      assert_equal unlock.expires_at, expire_time
    end
  end

  test "can be returned" do
    RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    unlock = RepositoryUnlock.with_staffer_and_repository(@staff, @repo)
    assert_equal unlock.repository, @repo
  end

  test "if multiple unlocks exist, returns the most recent" do
    another_grant = create :staff_access_grant, granted_by: @user, accessible: @repo, reason: "another reason"
    RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    Timecop.freeze(Time.now + 1.minute) do
      RepositoryUnlock.create_unlock(@staff, @repo, "another reason", another_grant)
    end

    unlock = RepositoryUnlock.with_staffer_and_repository(@staff, @repo)
    assert_equal "another reason", unlock.reason
  end

  test "starts out as active and not revoked" do
    unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    assert unlock.active?
  end

  test "can be revoked and made not active" do
    unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)
    assert_equal unlock.repository, @repo
    assert unlock.active?

    unlock.revoke(@user)

    assert unlock.revoked?
    assert !unlock.active?
  end

  test "if revoked, now has the time of the revoke" do
    unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)

    assert unlock.revoked_at.nil?
    unlock.revoke(@user)
    assert !unlock.revoked_at.nil?
  end

  test "is not active if it has expired" do
    unlock = RepositoryUnlock.create_unlock(@staff, @repo, @reason, @staff_grant)

    assert unlock.active?

    # Move ahead 5 hours
    Timecop.freeze(Time.now + 5.hours) do
      assert !unlock.active?
    end
  end

  test "cannot be created by non-staff" do
    assert_raises ActiveRecord::RecordInvalid do
      RepositoryUnlock.create_unlock(@user, @repo, @reason, @staff_grant)
    end

    unlock = RepositoryUnlock.find_by repository_id: @repo
    assert unlock.nil?
  end

  context "EMU admins", skip_enterprise: true do
    test "can be created for EMU user owned repo" do
      RepositoryUnlock.create_unlock(@emu_owner, @emu_owned_repo, "EMU admin unlocking emu user-owned repo")
      unlock = RepositoryUnlock.find_by! repository_id: @emu_owned_repo
      assert_equal unlock.repository, @emu_owned_repo
    end
  end
end
