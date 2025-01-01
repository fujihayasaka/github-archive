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

class RepositoryMembersWithInsecure2FAMethodsTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @org = create(:organization)
    @org.enable_two_factor_requirement(actor: @org.admin)
    @repo = create :repository, owner: @org

    @user = create(:user)
  end

  test "false if org does not exist" do
    repo = create :repository, owner: @user

    refute repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if disallow_two_factor_methods FF disabled" do
    GitHub.flipper[:disallow_two_factor_methods].disable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if members_without_2fa_allowed FF disabled" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].disable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if two_factor_cap_enforcement FF disabled" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].disable

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if user does not have 2FA enabled" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if there are no disallowed methods" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    make_two_factor_credential(@user)

    assert @org.get_two_factor_disallowed_methods.empty?
    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if user has 2FA enabled and has secure methods" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    make_two_factor_credential(@user)
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "true if user has 2FA enabled with primary SMS" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    make_sms_two_factor_credential(@user)
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    assert @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "true if user has 2FA enabled with a backup SMS" do
    GitHub.flipper[:disallow_two_factor_methods].enable
    GitHub.flipper[:members_without_2fa_allowed].enable
    GitHub.flipper[:two_factor_cap_enforcement].enable

    make_two_factor_credential(@user, backup_sms_number: "+1 2345556789")
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    assert @user.two_factor_backup_sms_registration?
    assert @repo.disallowed_two_factor_method_used_by?(@user)
  end
end
