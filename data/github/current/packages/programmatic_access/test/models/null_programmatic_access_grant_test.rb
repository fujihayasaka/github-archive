# typed: true
# frozen_string_literal: true

require "test_helper"

class NullProgrammaticAccessGrantTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers

  self.strict_fixtures = true
  fixtures do
    @user = create(:user)
    @pat  = create(:user_programmatic_access, owner: @user)
  end

  def null_grant
    @null_grant ||= NullProgrammaticAccessGrant.new(target: @pat.owner, user_programmatic_access: @pat)
  end

  test "sets target and user_programmatic_access" do
    assert_equal @pat.owner, null_grant.target
    assert_equal @pat, null_grant.user_programmatic_access
    assert_equal [], null_grant.permission_records
    assert_equal @pat.bot, null_grant.bot
  end

  test "overrides grantable methods" do
    assert_predicate null_grant, :can_have_granular_permissions?
    assert_nil null_grant.request
    assert_equal("none", null_grant.repository_selection)
    assert_equal(@pat, null_grant.ability_delegate_owner)
    assert_equal({}, null_grant.permissions)

    assert_empty null_grant.repository_ids
    assert_empty null_grant.repositories
  end

  test "has a nil id" do
    assert_nil null_grant.id
  end

  context "#can_have_granular_user_permissions?" do
    test "is true when the target is the owner of the access" do
      assert_predicate null_grant, :can_have_granular_user_permissions?
    end

    test "is false when the target is an org" do
      org = create(:organization, admin: @user)
      null_grant = NullProgrammaticAccessGrant.new(target: org, user_programmatic_access: @pat)

      refute_predicate null_grant, :can_have_granular_user_permissions?
    end

    test "is false when the target is a user but doesn't own the access" do
      user = create(:user)
      null_grant = NullProgrammaticAccessGrant.new(target: user, user_programmatic_access: @pat)

      refute_predicate null_grant, :can_have_granular_user_permissions?
    end
  end

  test "overrides ability methods" do
    assert_nil null_grant.ability_id
    assert_equal "NullProgrammaticAccessGrant", null_grant.ability_type
    assert_equal null_grant, null_grant.ability_delegate
  end

  test "overrides active record methods" do
    refute_predicate null_grant, :persisted?
  end

  test "returns an empty hash as permissions of any type" do
    assert_equal({}, null_grant.permissions_of_type("Repository"))
    assert_equal({}, null_grant.permissions_of_type("Organization"))
    assert_equal({}, null_grant.permissions_of_type("User"))
  end

  test "returns the target for #target_for_conditional_access" do
    assert_equal @pat.owner, null_grant.target_for_conditional_access
  end
end
