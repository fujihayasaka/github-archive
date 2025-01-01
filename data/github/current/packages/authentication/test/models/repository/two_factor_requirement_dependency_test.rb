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
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal false, repo.two_factor_requirement_met_by?(user)
  end

  test "async false if organization requires two factor authentication and prospective_member has not enabled it." do
    org = create(:organization)
    org.enable_two_factor_requirement(actor: org.admin)
    repo = create :repository, owner: org
    user = create(:user)
    assert_equal false, repo.async_two_factor_requirement_met_by?(user).sync
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

  test "false if user does not have 2FA enabled" do
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if there are no disallowed methods" do
    make_two_factor_credential(@user)

    assert @org.get_two_factor_disallowed_methods.empty?
    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "false if user has 2FA enabled and has secure methods" do
    make_two_factor_credential(@user)
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    refute @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "true if user has 2FA enabled with primary SMS" do
    make_sms_two_factor_credential(@user)
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    assert @repo.disallowed_two_factor_method_used_by?(@user)
  end

  test "true if user has 2FA enabled with a backup SMS" do
    make_two_factor_credential(@user, backup_sms_number: "+1 2345556789")
    @org.add_disallowed_two_factor_method(method: :insecure, actor: @org.admin)

    assert @user.two_factor_backup_sms_registration?
    assert @repo.disallowed_two_factor_method_used_by?(@user)
  end
end
