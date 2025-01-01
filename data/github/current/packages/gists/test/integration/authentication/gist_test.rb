# typed: true
# frozen_string_literal: true

require "test_helper"

class GitHub::Authentication::GistTest < GitHub::IntegrationTestCase
  fixtures do
    @user = create(:user, :verified, password: GitHub.default_password)
    @app_org = make_trusted_oauth_apps_owner
    @gist_app = create :oauth_application, user: @app_org,
                    callback_url: "http://gist.#{GitHub.host_name_with_tenant}/auth/github/callback"
    @gist_app_secret = @gist_app.generate_client_secret(creator: @user)

    @access  = create :oauth_access, application: @gist_app, user: @user

    @gist = GistHelpers.generate contents: [{ name: "hello.rb", value: "puts 'hello'" }]

    @github_host = GitHub.host_name_with_tenant
    @gist_host = "gist.#{GitHub.host_name_with_tenant}"  # to share cookies with subdomain for auto_oauth

    @@gist_host_name_before = GitHub.gist_host_name
    @@gist3_host_name_before = GitHub.gist3_host_name
    @@gist_oauth_client_id_before = GitHub.gist_oauth_client_id
    @@gist_oauth_secret_key_before = GitHub.gist_oauth_secret_key

    GitHub.gist_host_name = @gist_host
    GitHub.gist3_host_name = @gist_host
    GitHub.gist_oauth_client_id = @gist_app.key
    GitHub.gist_oauth_secret_key = @gist_app_secret
    GitHub.stubs(trusted_oauth_apps_owner: @app_org)

    # This should not be here. The gists are misconfigured in tests so that
    # even in dotcom mode they are hosted on the main domain under a prefix.
    # Reloading routes outside of a development environment is wrong, shouldn't
    # be done, and is very slow (30+ seconds on CI).
    # Do not copy this elsewhere.
    Rails.application.reload_routes!
  end

  teardown_once do
    GitHub.gist_host_name = @@gist_host_name_before
    GitHub.gist3_host_name = @@gist3_host_name_before
    GitHub.gist_oauth_client_id = @@gist_oauth_client_id_before
    GitHub.gist_oauth_secret_key = @@gist_oauth_secret_key_before

    # Do not copy this elsewhere. See above.
    Rails.application.reload_routes!
  end

  test "auto-oauths when user is logged into github but not gist" do
    host! @github_host
    login_as @user, GitHub.default_password

    host! @gist_host
    get "/"
    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/" }.to_param }"
    follow_redirect!

    assert_response :redirect
    assert_includes response.location, "#{@github_host}/login/oauth/authorize"
    follow_redirect!

    assert_redirected_to_url "http://#{@gist_host}/auth/github/callback"

    stub_oauth_client
    follow_redirect!

    assert_redirected_to "/"
    follow_redirect!

    assert_includes response.body, @user.display_login
    assert_select "[data-test-selector='header-logged-in']"
  end

  test "skips auto-oauth for embeds" do
    host! @github_host
    login_as @user, GitHub.default_password

    host! @gist_host

    # Sanity check that auto_oauth normally happens
    get "/"
    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/" }.to_param }"

    get "/#{@gist.name_with_display_owner}.js"
    assert_response :success
    assert_includes response.body, "hello.rb"

    get "/#{@gist.name_with_display_owner}.pibb"
    assert_response :success
    assert_includes response.body, "hello.rb"

    get "/#{@gist.repo_name}.js"
    assert_response :redirect
    assert_includes response.location,  "/#{@gist.name_with_display_owner}.js"

    get "/#{@gist.repo_name}.pibb"
    assert_response :redirect
    assert_includes response.location,  "/#{@gist.name_with_display_owner}.pibb"
  end

  test "restarts oauth dance on bad_verification_code error" do
    host! @github_host
    login_as @user, GitHub.default_password

    host! @gist_host
    get "/discover"
    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/discover" }.to_param }"
    follow_redirect!

    assert_response :redirect
    assert_includes response.location, "#{@github_host}/login/oauth/authorize"
    follow_redirect!

    assert_redirected_to_url "http://#{@gist_host}/auth/github/callback"

    stub_oauth_client_with_bad_code_error
    follow_redirect!

    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/discover" }.to_param }"
  end

  test "restarts if the access token is no longer valid due to race condition" do
    host! @github_host
    login_as @user, GitHub.default_password

    host! @gist_host
    get "/discover"
    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/discover" }.to_param }"
    follow_redirect!

    assert_response :redirect
    assert_includes response.location, "#{@github_host}/login/oauth/authorize"
    follow_redirect!

    assert_redirected_to_url "http://#{@gist_host}/auth/github/callback"

    stub_oauth_client_with_unauthorized_error
    follow_redirect!

    assert_redirected_to "/auth/github?#{ { return_to: "http://#{@gist_host}/discover" }.to_param }"
  end

  test "routes /users/diffview correctly" do
    host! @gist_host

    assert_routing(
      { method: :post, path: "http://#{@gist_host}/users/diffview" },
      { controller: "diff_view", action: "update_view_preference" },
    )
  end

  def stub_oauth_client
    user_response = stub("get_user_response", parsed: { "id" => @user.id })
    access_token = stub("access_token", options: Hash.new, get: user_response)
    auth_code = stub("auth_code", get_token: access_token)
    oauth2_client = stub("oauth2", auth_code: auth_code)

    Gists::SessionsController.any_instance.stubs(:client).returns(oauth2_client)

    oauth2_client
  end

  def stub_oauth_client_with_bad_code_error
    client = stub_oauth_client
    client.auth_code.stubs(:get_token).raises(bad_code_error)
  end

  def stub_oauth_client_with_unauthorized_error
    client = stub_oauth_client
    client.auth_code.get_token.stubs(:get).raises(unauthorized_error)
  end

  # This is less than ideal but we couldn't come up with a better way of
  # building out a valid OAuht2:Error. :(
  def bad_code_error
    github_response = {
      "error" => "bad_verification_code",
      "error_description" => "The code passed is incorrect or expired.",
      "error_uri" => "https://developer.github.com/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code",
    }
    response = stub("OAuth2::Response", "error=": true,
                                        parsed: github_response,
                                        body: github_response.to_json)
    OAuth2::Error.new response
  end

  def unauthorized_error
    github_response = {
      "message" => "Bad Credentials",
      "documentation_url" => "https://developer.github.com/v3",
    }
    response = stub("OAuth2::Response", "error=": true,
                                        parsed: github_response,
                                        body: github_response.to_json,
                                        status: 401)
    OAuth2::Error.new response
  end
end
