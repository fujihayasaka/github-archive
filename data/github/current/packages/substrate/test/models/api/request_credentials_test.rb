# typed: true
# frozen_string_literal: true

require "test_helper"
require "rack"

class MockRequest
  attr_writer :env
  attr_accessor :login, :password, :otp, :params, :proxima_service_token

  def initialize(options = {})
    @login                 = options[:login]
    @password              = options[:password]
    @otp                   = options[:otp]
    @auth_header           = options[:auth_header]
    @params                = options[:params]
    @proxima_service_token = options[:proxima_service_token]
  end

  def env
    env = auth_header
      .merge(otp_header)
      .merge(proxima_service_header)
      .merge("REQUEST_METHOD" => "GET")
      .merge(params: @params)
    Rack::MockRequest.env_for("/somepath", env)
  end

  def auth_header
    return @auth_header if @auth_header
    return {} unless login && password
    value = "Basic " + Base64.strict_encode64("#{login}:#{password}")
    @auth_header = { "HTTP_AUTHORIZATION" => value }
  end

  def otp_header
    return @otp_header if @otp_header
    @otp_header = { "HTTP_X_GITHUB_OTP" => otp }
  end

  def proxima_service_header
    return @proxima_service_header if @proxima_service_header
    return {} unless proxima_service_token
    @proxima_service_header = { "HTTP_X_GITHUB_PSI_JWT" => proxima_service_token }
  end
end

class RequestCredentialsTest < GitHub::TestCase
  fixtures do
    @login = "login"
    @password = "password"
    @otp = "123456"
    @basic_auth_creds = Base64.strict_encode64([@login, @password].join(":"))
    @access_token = "a1" * 20
    @integration_token = "v1.0000000000000000000000000000000000000000"
    @authnd_token = "github_pat_1#{SecureRandom.alphanumeric(21)}_#{SecureRandom.alphanumeric(59)}" # fine-grained pat token format

    @proxima_service_secret = "abcdefgh123456"
    @proxima_service_token = ProximaServiceToken.generate(stamp: "staff-wus2-01", tenant_shortcode: "test-tenant", service_name: "actions", secret: @proxima_service_secret)
  end

  setup do
    GitHub.flipper[:proxima_service_rate_limits].enable
  end

  context ".token_from_scheme" do
    test "pulls a token from an HTTP_AUTHORIZATION header" do
      env = { "HTTP_AUTHORIZATION" => "TOKEN mylittletoken" }
      value = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_equal value, "mylittletoken"
    end

    test "pulls a token from an X-HTTP_AUTHORIZATION header" do
      env = { "X-HTTP_AUTHORIZATION" => "TOKEN mylittletoken" }
      value = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_equal value, "mylittletoken"
    end

    test "pulls a token from a custom X_HTTP_AUTHORIZATION header" do
      env = { "X_HTTP_AUTHORIZATION" => "TOKEN mylittletoken" }
      value = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_equal value, "mylittletoken"
    end

    test "returns no token if the header is present but does not match" do
      env = { "HTTP_AUTHORIZATION" => "Bearer mylittletoken" }
      value = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_nil value
    end

    test "returns no token if there is no accepted authorization header" do
      env = { "X-BOGUS_AUTHORIZATION" => "token mylittletoken" }
      value = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_nil value
    end
  end

  context ".login_password_from_basic" do
    test "pull a login and password token from an HTTP_AUTHORIZATION header" do
      env = { "HTTP_AUTHORIZATION" => "basic #{@basic_auth_creds}" }
      login, password = Api::RequestCredentials.login_password_from_basic(env)

      assert_equal login, "login"
      assert_equal password, "password"
    end

    test "uses a regex to pull a token from an X-HTTP_AUTHORIZATION header" do
      env = { "X-HTTP_AUTHORIZATION" => "basic #{@basic_auth_creds}" }
      login, password = Api::RequestCredentials.login_password_from_basic(env)

      assert_equal login, "login"
      assert_equal password, "password"
    end

    test "uses a regex to pull a token from a custom X_HTTP_AUTHORIZATION header" do
      env = { "X_HTTP_AUTHORIZATION" => "basic #{@basic_auth_creds}" }
      login, password = Api::RequestCredentials.login_password_from_basic(env)

      assert_equal login, "login"
      assert_equal password, "password"
    end

    test "returns no login or password if there is no accepted authorization header" do
      env = { "X-BOGUS_AUTHORIZATION" => "basic #{@basic_auth_creds}" }
      login, password = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_nil login
      assert_nil password
    end

    test "returns no login or password if there is no basic scheme in authorization header" do
      env = { "X-BOGUS_AUTHORIZATION" => "token #{@basic_auth_creds}" }
      login, password = Api::RequestCredentials.token_from_scheme(env, "token")

      assert_nil login
      assert_nil password
    end
  end

  context ".from_env" do
    test "sets login and password and otp" do
      request = MockRequest.new(login: @login, password: @password, otp: @otp)
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @login, creds.login
      assert_equal @password, creds.password
      assert_equal @otp, creds.otp
    end

    test "sets token automatically if password looks like an access token" do
      request = MockRequest.new(login: @login, password: @access_token)
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @login, creds.login
      assert_equal @access_token, creds.password
      assert_equal @access_token, creds.token
    end

    test "sets token automatically if password looks like an integration token" do
      request = MockRequest.new(
        login: @login,
        password: @integration_token,
      )
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @login, creds.login
      assert_equal @integration_token, creds.password
      assert_equal @integration_token, creds.token
    end

    test "sets token automatically if login looks like an access token and password is blank" do
      request = MockRequest.new(login: @access_token, password: "")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @access_token, creds.login
      assert creds.password.blank?
      assert_equal @access_token, creds.token
    end

    test "doesn't set token automatically if login looks like an integration token and password is blank" do
      request = MockRequest.new(login: @integration_token, password: "")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @integration_token, creds.login
      assert creds.password.blank?
      assert_nil creds.token
    end

    test "sets token automatically if login looks like an access token and password is x-oauth-basic" do
      request = MockRequest.new(login: @access_token, password: "x-oauth-basic")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @access_token, creds.login
      assert_equal "x-oauth-basic", creds.password
      assert_equal @access_token, creds.token
    end

    test "doesn't set token automatically if login looks like an access token and password is not x-oauth-basic" do
      request = MockRequest.new(login: @access_token, password: "not-x-oauth-basic")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @access_token, creds.login
      assert_equal "not-x-oauth-basic", creds.password
      assert_nil creds.token
    end

    test "doesn't set token automatically if login looks like an integration token and password is x-oauth-basic" do
      request = MockRequest.new(login: @integration_token, password: "x-oauth-basic")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @integration_token, creds.login
      assert_equal "x-oauth-basic", creds.password
      assert_nil creds.token
    end

    test "sets token automatically if the loginc looks like and authnd token and password is x-oauth-basic" do
      request = MockRequest.new(login: @authnd_token, password: "x-oauth-basic")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @authnd_token, creds.login
      assert_equal "x-oauth-basic", creds.password
      assert_equal @authnd_token, creds.token
    end

    test "doesn't set token automatically if login looks like an authnd token and password is not x-oauth-basic" do
      request = MockRequest.new(login: @authnd_token, password: "not-x-oauth-basic")
      creds = Api::RequestCredentials.from_env(request.env)

      assert_equal @authnd_token, creds.login
      assert_equal "not-x-oauth-basic", creds.password
      assert_nil creds.token
    end

    test "sets token automatically if found in authorization header" do
      Api::RequestCredentials::AUTHORIZATION_SCHEMES.each do |scheme|
        request = MockRequest.new(
          auth_header: { "HTTP_AUTHORIZATION" => "#{scheme} #{@access_token}" },
        )
        creds = Api::RequestCredentials.from_env(request.env)
        assert_nil creds.login
        assert_nil creds.password
        assert_equal @access_token, creds.token
      end
    end

    test "doesn't set token if found in authorization header, but headers support is disabled" do
      Api::RequestCredentials::AUTHORIZATION_SCHEMES.each do |scheme|
        request = MockRequest.new(
          auth_header: { "HTTP_AUTHORIZATION" => "#{scheme} #{@access_token}" },
        )
        creds = Api::RequestCredentials.from_env(request.env, headers: false)
        assert_nil creds.login
        assert_nil creds.password
        assert_nil creds.token
      end
    end

    test "#via_params? is false if found in an authorization header" do
      Api::RequestCredentials::AUTHORIZATION_SCHEMES.each do |scheme|
        request = MockRequest.new(
          auth_header: { "HTTP_AUTHORIZATION" => "#{scheme} #{@access_token}" },
        )
        creds = Api::RequestCredentials.from_env(request.env)
        refute_predicate creds, :via_params?
      end
    end

    test "#via_params? is false if found in an authorization header, but headers support is disabled" do
      Api::RequestCredentials::AUTHORIZATION_SCHEMES.each do |scheme|
        request = MockRequest.new(
          auth_header: { "HTTP_AUTHORIZATION" => "#{scheme} #{@access_token}" },
        )
        creds = Api::RequestCredentials.from_env(request.env, headers: false)
        refute_predicate creds, :via_params?
      end
    end

    test "sets token automatically if found in a query parameter" do
      Api::RequestCredentials::TOKEN_PARAMS.each do |param|
        request = MockRequest.new(
          params: { param.to_sym => @access_token },
        )
        creds = Api::RequestCredentials.from_env(request.env)
        assert_nil creds.login
        assert_nil creds.password
        assert_equal @access_token, creds.token
      end
    end

    test "doesn't set token automatically if found in a query parameter, but params support is disabled" do
      Api::RequestCredentials::TOKEN_PARAMS.each do |param|
        request = MockRequest.new(
          params: { param.to_sym => @access_token },
        )
        creds = Api::RequestCredentials.from_env(request.env, params: false)
        assert_nil creds.login
        assert_nil creds.password
        assert_nil creds.token
      end
    end

    test "#via_params? is true if found in a query parameter" do
      Api::RequestCredentials::TOKEN_PARAMS.each do |param|
        request = MockRequest.new(
          params: { param.to_sym => @access_token },
        )
        creds = Api::RequestCredentials.from_env(request.env)
        assert_predicate creds, :via_params?
      end
    end

    test "#via_params? is false if found in a query parameter, but params support is disabled" do
      Api::RequestCredentials::TOKEN_PARAMS.each do |param|
        request = MockRequest.new(
          params: { param.to_sym => @access_token },
        )
        creds = Api::RequestCredentials.from_env(request.env, params: false)
        refute_predicate creds, :via_params?
      end
    end

    test "prefers login and password over token parameter" do
      request = MockRequest.new(
        login: @login,
        password: @password,
        params: { "access_token": @access_token },
      )
      creds = Api::RequestCredentials.from_env(request.env)
      assert_equal @login, creds.login
      assert_equal @password, creds.password
      assert_nil creds.token
    end

    test "prefers token in authorization header over token in parameter" do
      token1 = "a1" * 20
      token2 = "a2" * 20
      request = MockRequest.new(
        auth_header: { "HTTP_AUTHORIZATION" => "token #{token1}" },
        params: { "access_token": token2 },
      )
      creds = Api::RequestCredentials.from_env(request.env)
      assert_nil creds.login
      assert_nil creds.password
      assert_equal token1, creds.token
    end

    context "when the token is invalid UTF-8 or non-ascii" do
      test "does not set the token when found in a query parameter" do
        invalid_token = CGI.unescape("%8F%A0%A2%A5%AB")
        Api::RequestCredentials::TOKEN_PARAMS.each do |param|
          request = MockRequest.new(
            params: { param.to_sym => invalid_token },
          )
          creds = Api::RequestCredentials.from_env(request.env)
          assert_nil creds.login
          assert_nil creds.password
          assert_equal false, creds.token_present?
          assert_nil creds.token
        end
      end

      test "does not set the token when initializer used" do
        invalid_token = CGI.unescape("%8F%A0%A2%A5%AB")
        creds = Api::RequestCredentials.new(token: invalid_token)
        assert_nil creds.login
        assert_nil creds.password
        assert_equal false, creds.token_present?
        assert_nil creds.token
      end

      test "#via_params? is false when found in a query parameter" do
        invalid_token = CGI.unescape("%8F%A0%A2%A5%AB")
        Api::RequestCredentials::TOKEN_PARAMS.each do |param|
          request = MockRequest.new(
            params: { param.to_sym => invalid_token },
          )
          creds = Api::RequestCredentials.from_env(request.env)
          refute_predicate creds, :via_params?
        end
      end
    end

    context "proxima service token" do
      test "respected for anonymous requests" do
        request = MockRequest.new(
          proxima_service_token: @proxima_service_token,
        )
        GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
        creds = Api::RequestCredentials.from_env(request.env, headers: true)
        assert creds.proxima_service_token_present?
        assert_equal @proxima_service_token, creds.proxima_service_token
        assert_equal 1, GitHub.dogstats.increments("api.proxima_service_token.received").length
      end

      test "ignored when feature flag disabled" do
        GitHub.flipper[:proxima_service_rate_limits].disable

        request = MockRequest.new(
          proxima_service_token: @proxima_service_token,
        )
        creds = Api::RequestCredentials.from_env(request.env, headers: true)
        refute creds.proxima_service_token_present?
        refute creds.proxima_service_token
      end


      test "overriden by bearer token" do
        Api::RequestCredentials::AUTHORIZATION_SCHEMES.each do |scheme|
          request = MockRequest.new(
            auth_header: { "HTTP_AUTHORIZATION" => "#{scheme} #{@access_token}" },
            proxima_service_token: @proxima_service_token,
          )
          creds = Api::RequestCredentials.from_env(request.env, headers: true)
          assert_equal @access_token, creds.token
          refute creds.proxima_service_token
          refute creds.proxima_service_token_present?
        end
      end

      test "overridden by basic auth" do
        request = MockRequest.new(
          login: @login,
          password: @password,
          otp: @otp,
          proxima_service_token: @proxima_service_token,
        )
        creds = Api::RequestCredentials.from_env(request.env)

        assert_equal @login, creds.login
        assert_equal @password, creds.password
        assert_equal @otp, creds.otp
        refute creds.proxima_service_token
        refute creds.proxima_service_token_present?
      end

      test "overriden by query parameter" do
        Api::RequestCredentials::TOKEN_PARAMS.each do |param|
          request = MockRequest.new(
            params: { param.to_sym => @access_token },
            proxima_service_token: @proxima_service_token,
          )
          creds = Api::RequestCredentials.from_env(request.env)
          assert_equal @access_token, creds.token
          refute creds.proxima_service_token
          refute creds.proxima_service_token_present?
        end
      end
    end
  end
end
