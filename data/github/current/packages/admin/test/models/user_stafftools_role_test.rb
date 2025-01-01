# typed: true
# frozen_string_literal: true

require "test_helper"

class UserStafftoolsRoleTest < GitHub::TestCase

  fixtures do
    @user = create :staff_admin_user
    @role = StafftoolsRole.new(name: "test")
    @role.save
  end

  test "validates presence of user and staff tool role" do
    join = UserStafftoolsRole.new
    refute join.valid?
    assert_includes join.errors[:user], "can't be blank"
    assert_includes join.errors[:stafftools_role], "can't be blank"
  end

  test "validates uniqueness of name" do
    dupe_role = StafftoolsRole.new(name: "test")
    refute dupe_role.valid?
    assert dupe_role.errors[:name].include? "has already been taken"

    dupe_role = StafftoolsRole.new(name: "TEST")
    refute dupe_role.valid?
    assert dupe_role.errors[:name].include? "has already been taken"
  end

  test "can't be assigned the same role twice" do
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save

    assignment2 = UserStafftoolsRole.new(user: @user, stafftools_role: @role)

    refute assignment2.valid?
    assert_includes assignment2.errors[:stafftools_role_id], "Role already assigned to user"
  end

  test "role can be assigned to 2 users" do
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save

    user2 = create :staff_admin_user
    assignment2 = UserStafftoolsRole.new(user: user2, stafftools_role: @role)

    assert assignment2.valid?
  end

  test "staff tools roles must be assigned to a staff user" do
    user = create :user
    assignment = UserStafftoolsRole.new(user: user, stafftools_role: @role)

    refute assignment.valid?
    assert_equal "User #{user.login} must be a site admin to be assigned stafftools roles",
      assignment.errors[:user_staff_admin].first
  end

  # ways we could assign << on user, UserStafftoolsRole.new
  test "calls log role assignment after creation" do
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.expects(:log_role_assignment)
    assignment.save
  end

  test "audits role assignment" do
    events = subscribe "stafftools_role.assignment"
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      role: @role.name,
      role_id: @role.id,
    }

    assert event = events.pop
    assert_equal "stafftools_role.assignment", event.name
    assert_equal expected_payload, event.payload
  end

  test "calls log role removal after deletion" do
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save
    assignment.expects(:log_role_removal)
    assignment.destroy
  end

  test "audits role removal" do
    events = subscribe "stafftools_role.removal"
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save
    @user.reload
    @user.stafftools_roles.destroy_all

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      role: @role.name,
      role_id: @role.id,
    }

    assert event = events.pop
    assert_equal "stafftools_role.removal", event.name
    assert_equal expected_payload, event.payload
  end

  test "removing a user's stafftools access also removes staff tools roles" do
    assignment = UserStafftoolsRole.new(user: @user, stafftools_role: @role)
    assignment.save
    role2 = StafftoolsRole.new(name: "test2")
    role2.save
    assignment2 = UserStafftoolsRole.new(user: @user, stafftools_role: role2)
    assignment2.save

    @user.reload
    assert_equal 2, @user.stafftools_roles.length

    @user.revoke_privileged_access("demote")
    permissions = UserStafftoolsRole.where(user_id: @user.id)

    @user.reload
    assert_equal 0, @user.stafftools_roles.length
  end
end
