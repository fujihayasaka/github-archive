# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::RevokeWebEditorTokensTest < GitHub::TestCase

  fixtures do
    @user = create(:user)
    @vscode = create(:vscode_oauth_app)
    @lwe = create(:lwe_oauth_app)

    @apps = [@vscode, @lwe]
  end

  def issue_tokens(user)
    2.times do
      @apps.each do |app|
        app.grant(user).redeem
      end
    end
  end

  test "revokes LWE authorizations and accesses, but not other apps'" do
    issue_tokens(@user)
    assert_equal(1, @user.oauth_authorizations.where(application: @lwe).count, "expected 1 lwe authz before revoke")
    assert_equal(2, @user.oauth_accesses.where(application: @lwe).count, "expected 2 lwe access before revoke")
    assert_equal(1, @user.oauth_authorizations.where(application: @vscode).count, "expected 1 vscode authz before revoke")
    assert_equal(2, @user.oauth_accesses.where(application: @vscode).count, "expected 2 vscode access before revoke")
    result = Codespaces::RevokeWebEditorTokens.call(user: @user, timeout: 10, entry_point: :test_case)
    assert_equal(Codespaces::RevokeWebEditorTokens::Result::Success, result)
    assert_equal(0, @user.oauth_authorizations.where(application: @lwe).count, "expected all lwe authz revoked")
    assert_equal(0, @user.oauth_accesses.where(application: @lwe).count, "expected all lwe accesses revoked")
    assert_equal(1, @user.oauth_authorizations.where(application: @vscode).count, "expected vscode authz not to change after lwe revoke")
    assert_equal(2, @user.oauth_accesses.where(application: @vscode).count, "expected vscode access not to change after lwe revoke")
  end

  test "revokes the user's LWE authorizations and accesses, but not other users'" do
    other = create(:user)
    issue_tokens(@user)
    issue_tokens(other)
    assert_equal(1, @user.oauth_authorizations.where(application: @lwe).count, "expected 1 lwe authz before revoke")
    assert_equal(2, @user.oauth_accesses.where(application: @lwe).count, "expected 2 lwe access before revoke")
    assert_equal(1, other.oauth_authorizations.where(application: @lwe).count, "expected 1 lwe authz before revoke")
    assert_equal(2, other.oauth_accesses.where(application: @lwe).count, "expected 2 lwe access before revoke")
    result = Codespaces::RevokeWebEditorTokens.call(user: @user, timeout: 10, entry_point: :test_case)
    assert_equal(Codespaces::RevokeWebEditorTokens::Result::Success, result)
    assert_equal(0, @user.oauth_authorizations.where(application: @lwe).count, "expected all lwe authz revoked")
    assert_equal(0, @user.oauth_accesses.where(application: @lwe).count, "expected all lwe accesses revoked")
    assert_equal(1, other.oauth_authorizations.where(application: @lwe).count, "expected no lwe authz revoked from other user")
    assert_equal(2, other.oauth_accesses.where(application: @lwe).count, "expected no lwe accesses revoked from other user")
  end

  test "bails if time is short" do
    issue_tokens(@user)
    assert_equal(1, @user.oauth_authorizations.where(application: @lwe).count, "expected 1 lwe authz before revoke")
    assert_equal(2, @user.oauth_accesses.where(application: @lwe).count, "expected 2 lwe access before revoke")
    result = Codespaces::RevokeWebEditorTokens.call(user: @user, timeout: 0.00000000001, entry_point: :test_case)
    assert_equal(Codespaces::RevokeWebEditorTokens::Result::TimedOut, result)
    assert_equal(1, @user.oauth_authorizations.where(application: @lwe).count, "expected no revocation")
    assert_equal(2, @user.oauth_accesses.where(application: @lwe).count, "expected no revocation")
  end
end
