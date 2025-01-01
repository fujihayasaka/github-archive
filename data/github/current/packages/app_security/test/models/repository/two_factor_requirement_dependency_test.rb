# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryTwoFactorRequirementMetByTest < GitHub::TestCase
  test "true if organization is nil" do
    repo = create :repository, owner: create(:user)
    user = create(:user)
    assert_equal true, repo.two_factor_requirement_met_by?(user)
  end

  test "async true if organization is nil" do
    repo = create :repository, owner: create(:user)
    user = create(:user)
    assert_equal true, repo.async_two_factor_requirement_met_by?(user).sync
  end

  test "true if organization does not require two factor authentation" do
    org = create(:organization)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal true, repo.two_factor_requirement_met_by?(user)
  end

  test "async true if organization does not require two factor authentication" do
    org = create(:organization)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal true, repo.async_two_factor_requirement_met_by?(user).sync
  end

  test "true if organization requires two factor authentication and prospective_member has enabled it" do
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:two_factor_credential_user)
    assert_equal true, repo.two_factor_requirement_met_by?(user)
  end

  test "async true if organization requires two factor authentication and prospective_member has enabled it" do
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:two_factor_credential_user)
    assert_equal true, repo.async_two_factor_requirement_met_by?(user).sync
  end

  test "false if organization requires two factor authentication and prospective_member has not enabled it." do
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal false, repo.two_factor_requirement_met_by?(user)
  end

  test "async false if organization requires two factor authentication and prospective_member has not enabled it." do
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal false, repo.async_two_factor_requirement_met_by?(user).sync
  end
end

class RepositoryMembersWithout2faAllowedTest < GitHub::TestCase
  test "true if organization is nil" do
    repo = create :repository, owner: create(:user)
    assert_equal true, repo.members_without_2fa_allowed?
  end

  test "async true if organization is nil" do
    repo = create :repository, owner: create(:user)
    assert_equal true, repo.async_members_without_2fa_allowed?.sync
  end

  test "true if two_factor_cap_enforcement and members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal true, repo.members_without_2fa_allowed?
  end

  test "async true if two_factor_cap_enforcement and members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal true, repo.async_members_without_2fa_allowed?.sync
  end

  test "false if not two_factor_cap_enforcement" do
    GitHub.flipper[:two_factor_cap_enforcement].disable
    GitHub.flipper[:members_without_2fa_allowed].enable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.members_without_2fa_allowed?
  end

  test "async false if not two_factor_cap_enforcement" do
    GitHub.flipper[:two_factor_cap_enforcement].disable
    GitHub.flipper[:members_without_2fa_allowed].enable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.async_members_without_2fa_allowed?.sync
  end

  test "false if not members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.async_members_without_2fa_allowed?.sync
  end

  test "async false if not members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].enable
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.async_members_without_2fa_allowed?.sync
  end

  test "false if not two_factor_cap_enforcement and not members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].disable
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.async_members_without_2fa_allowed?.sync
  end

  test "async false if not two_factor_cap_enforcement and not members_without_2fa_allowed" do
    GitHub.flipper[:two_factor_cap_enforcement].disable
    GitHub.flipper[:members_without_2fa_allowed].disable
    org = create(:organization)
    repo = create :repository, owner: org
    assert_equal false, repo.async_members_without_2fa_allowed?.sync
  end
end
