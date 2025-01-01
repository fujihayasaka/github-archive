# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryAddMemberTest < GitHub::TestCase
  fixtures do
    @org = create(:two_factor_credential_org)
    @org_repo = create(:private_repository, owner: @org)
    @user = create(:paid_user)
    @user_repo = create(:private_repository, owner: @user)
  end

  test "does not add member to private org repo if 2fa requirement is not met" do
    GitHub.flipper[:members_without_2fa_allowed].disable
    addee = create(:user)
    @org_repo.add_member(addee)

    refute_includes @org_repo.members, addee
  end

  test "adds member to private org repo if 2fa requirement is not met but CAP enforcement is enabled" do
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:cap_2fa_policy_enabled].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable
    addee = create(:user)
    @org_repo.add_member(addee)

    assert_includes @org_repo.members, addee
  end

  test "adds member to private org repo if 2fa requirement is met" do
    addee = create(:user)
    make_two_factor_credential(addee)
    @org_repo.add_member(addee)

    assert_includes @org_repo.members, addee
  end

  test "adds member to private user repo" do
    addee = create(:user)
    @user_repo.add_member(addee)

    assert_includes @user_repo.members, addee
  end
end
