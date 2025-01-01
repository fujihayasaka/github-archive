# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthApplicationPolicyHttpRequestTest < GitHub::TestCase
  fixtures do
    @user = create :user, plan: "medium"
    @org = create :organization, admin: @user, plan: "bronze", login: "stark-industries"
    @pub_repo = create :repository, :minimal, owner: @org, name: "pub"
    @priv_repo = create :repository, :minimal, owner: @org, name: "priv"
    @oauth_app = create :oauth_application, name: "Janky"
    @app_access = make_oauth(@user, %w(repo), @oauth_app)

    @org.enable_oauth_application_restrictions

    OauthApplicationPolicy::Application.any_instance.stubs(:satisfied?).returns(false)
  end

  context "#satisfied?" do
    test "returns true for public repos for non-mutating requests" do
      user = User.with_oauth_hashed_token(@app_access.hashed_token)
      assert OauthApplicationPolicy::HttpRequest.new(
        repository: @pub_repo,
        user: user,
        request: non_mutating_request,
      ).satisfied?
    end

    test "returns false for private repos" do
      user = User.with_oauth_hashed_token(@app_access.hashed_token)
      assert OauthApplicationPolicy::HttpRequest.new(
        repository: @priv_repo,
        user: user,
        request: non_mutating_request,
      ).satisfied?
    end

    test "returns true for private repos for non-mutating requests" do
      user = User.with_oauth_hashed_token(@app_access.hashed_token)
      assert OauthApplicationPolicy::HttpRequest.new(
        repository: @priv_repo,
        user: user,
        request: non_mutating_request,
      ).satisfied?
    end

    test "returns false for public repos for mutating requests" do
      user = User.with_oauth_hashed_token(@app_access.hashed_token)
      assert !OauthApplicationPolicy::HttpRequest.new(
        repository: @pub_repo,
        user: user,
        request: mutating_request,
      ).satisfied?
    end

    test "returns false for private repos for mutating requests" do
      user = User.with_oauth_hashed_token(@app_access.hashed_token)
      assert !OauthApplicationPolicy::HttpRequest.new(
        repository: @priv_repo,
        user: user,
        request: mutating_request,
      ).satisfied?
    end

    test "returns true for personal access tokens" do
      personal_access = create(:personal_token_oauth_access, user: @user, scopes: %w(repo))
      user = User.with_oauth_hashed_token(personal_access.hashed_token)

      assert OauthApplicationPolicy::HttpRequest.new(
        repository: @priv_repo,
        user: user,
        request: mutating_request,
      ).satisfied?
    end
  end

  def mutating_request
    env = { "REQUEST_METHOD" => "POST" }

    Rack::Request.new(env)
  end

  def non_mutating_request
    env = { "REQUEST_METHOD" => "GET" }

    Rack::Request.new(env)
  end
end if GitHub.oauth_application_policies_enabled?
