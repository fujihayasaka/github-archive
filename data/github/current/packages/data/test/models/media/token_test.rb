# typed: true
# frozen_string_literal: true

require "test_helper"

class MediaTokenTest < GitHub::TestCase

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user         = create :user
    @repo         = create :repository, owner: @user
    @scope        = "some_scope"
    @key          = create :public_key, repository: @repo
    @expires      = 1.hour.from_now
    @org          = create :organization, admin: @user
    @integration  = create :integration, bot: @bot
    @installation = make_integration_installation(
      target: TestEnv.test_with_all_emus? ? @org : @user,
      integration: @integration,
    )
    @scoped_installation = make_scoped_integration_installation(
      parent: @installation,
      repositories: [@repo],
    )
    @bot = @scoped_installation.bot
  end

  setup do
    GitHub.preview_features_enabled = true
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "gitauth_token_for_user returns valid token for user" do
    token = Media::Token.gitauth_token_for_user(@user, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert verify.valid?
    assert_equal verify.user, @user
    assert_nil verify.public_key
  end

  test "gitauth_token_for_user returns valid token for bot" do
    token = Media::Token.gitauth_token_for_user(@bot, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert verify.valid?
    assert_equal verify.user, @bot
    assert_nil verify.public_key
  end

  test "gitauth_token_for_deploy_key returns valid token for key" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert verify.valid?
    assert_equal verify.public_key, @key
    assert_nil verify.user
  end

  test "user_for_token returns user with gitauth token" do
    token = Media::Token.gitauth_token_for_user(@user, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_equal Media::Token.user_for_token(verify), @user
  end

  test "user_for_token returns bot with gitauth token" do
    token = Media::Token.gitauth_token_for_user(@bot, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_equal Media::Token.user_for_token(verify), @bot
  end

  test "user_for_token returns nil with deploy key gitauth token" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_nil Media::Token.user_for_token(verify)
  end

  test "user_for_token returns user with signed auth token" do
    token = @user.signed_auth_token(scope: @scope)
    verify = User.verify_signed_auth_token token: token, scope: @scope
    assert_equal Media::Token.user_for_token(verify), @user
  end

  test "user_for_token returns bot with signed auth token" do
    token = @bot.signed_auth_token(scope: @scope)
    verify = User.verify_signed_auth_token token: token, scope: @scope
    assert_equal Media::Token.user_for_token(verify), @bot
  end

  test "SATs token data should only be initialized with content" do
    # this is a bot SAT specific problem
    token = @bot.signed_auth_token(scope: @scope)
    GitHub::Authentication::SignedAuthToken.verify(token: token, scope: @scope).tap do |token|
      refute token.data.is_a?(Hash)
      assert_nil token.data
    end

    # gitauth bot SATs should always have data, but we can check anyways for future proofing
    repo_token = Media::Token.gitauth_token_for_user(@bot, @scope, @repo, @expires)
    verify = verify_token token: repo_token, scope: @scope, repo: @repo
    if verify.data&.empty?
      refute verify.data.is_a?(Hash)
      assert_nil verify.data
    end
  end

  test "user_for_token returns nil with invalid gitauth token" do
    token = Media::Token.gitauth_token_for_user(@user, "bad scope", @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_nil Media::Token.user_for_token(verify)
  end

  test "user_for_token returns nil with invalid signed auth token" do
    token = @user.signed_auth_token(scope: "bad scope")
    verify = User.verify_signed_auth_token token: token, scope: @scope
    assert_nil Media::Token.user_for_token(verify)
  end

  test "deploy_key_for_token returns key with gitauth token" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_equal Media::Token.deploy_key_for_token(verify), @key
  end

  test "deploy_key_for_token returns nil with signed auth token" do
    token = @user.signed_auth_token(scope: @scope)
    verify = User.verify_signed_auth_token token: token, scope: @scope
    assert_nil Media::Token.deploy_key_for_token(verify)
  end

  test "deploy_key_for_token returns nil with invalid gitauth token" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, "bad scope", @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_nil Media::Token.deploy_key_for_token(verify)
  end

  test "repo_key_for_token returns repo with gitauth token" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, @scope, @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_equal Media::Token.repo_for_token(verify), @repo
  end

  test "repo_for_token returns nil with signed auth token" do
    token = @user.signed_auth_token(scope: @scope)
    verify = User.verify_signed_auth_token token: token, scope: @scope
    assert_nil Media::Token.repo_for_token(verify)
  end

  test "repo_for_token returns nil with invalid gitauth token" do
    token = Media::Token.gitauth_token_for_deploy_key(@key, "bad scope", @repo, @expires)
    verify = verify_token token: token, scope: @scope, repo: @repo
    assert_nil Media::Token.repo_for_token(verify)
  end

  def verify_token(options = {})
    GitHub::Authentication::GitAuth::SignedAuthToken.verify(options)
  end
end
