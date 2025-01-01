# typed: true
# frozen_string_literal: true

require "test_helper"

class RequestAuthenticationFingerprintTest < GitHub::TestCase
  include AuthenticationHelpers::JWT

  fixtures do
    @fine_grained_pat = "github_pat_1#{SecureRandom.alphanumeric(21)}_#{SecureRandom.alphanumeric(59)}" # fine-grained pat token format
    @fine_grained_pat_last_eight = @fine_grained_pat.last(8)
    @fine_grained_pat_hash = ProgrammaticAccessTokens.domain.hash_token(@fine_grained_pat)
    @user = create(:user)
  end

  test "uses remote ip for anonymous requests" do
    assert_equal "207.207.0.3", fingerprint.to_s
  end

  test "uses last eight and remote IP for token in hmac header" do
    env = {
      "HTTP_REQUEST_HMAC" => "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9",
    }
    assert_equal "hmac:1c9db4d9:207.207.0.3", fingerprint(env).to_s
  end

  test "uses only last eight characters for token in hmac header when omit_ip is true" do
    env = {
      "HTTP_REQUEST_HMAC" => "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9",
    }
    assert_equal "hmac:1c9db4d9", fingerprint(env, omit_ip: true).to_s
  end

  test "uses last eight characters of jwt token and remote IP from psi header" do
    enable_feature_flag(:proxima_service_rate_limits_secondary)
    env = {
      "HTTP_X_GITHUB_PSI_JWT" => "de7c9b85b8b7.8aa6bc8a7a36f70.a90701c9db4d9",
    }
    assert_equal "psi:1c9db4d9:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight characters of jwt token from psi header when omit_ip is true" do
    enable_feature_flag(:proxima_service_rate_limits_secondary)
    env = {
      "HTTP_X_GITHUB_PSI_JWT" => "de7c9b85b8b7.8aa6bc8a7a36f70.a90701c9db4d9",
    }
    assert_equal "psi:1c9db4d9", fingerprint(env, omit_ip: true).to_s
  end

  test "doesn't use last eight of HMAC when the header is empty" do
    env = {
      "HTTP_REQUEST_HMAC" => "",
      "HTTP_X_SSL_JA3_Hash" => "JA3_HASH",
    }
    assert_equal "207.207.0.3", fingerprint(env).to_s

    env = {
      "HTTP_REQUEST_HMAC" => nil,
    }

    assert_equal "207.207.0.3", fingerprint(env).to_s
  end

  test "uses IP address with JA3 hash when the header is empty" do
    env = {
      "HTTP_REQUEST_HMAC" => "",
      "HTTP_X_SSL_JA3_HASH" => "JA3_HASH",
    }
    assert_equal "207.207.0.3:JA3_HASH", fingerprint(env).to_s
  end

  test "uses JA3 hash when the header is empty and omit_ip is true" do
    env = {
      "HTTP_REQUEST_HMAC" => "",
      "HTTP_X_SSL_JA3_HASH" => "JA3_HASH",
    }
    assert_equal "JA3_HASH", fingerprint(env, omit_ip: true).to_s
  end

  test "uses last eight characters for access token in auth header when omit_ip is true" do
    env = {
      "HTTP_AUTHORIZATION" => "token d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f",
    }
    assert_equal "token:aec8f36f", fingerprint(env, omit_ip: true).to_s
  end

  test "uses last eight and remote IP for access token in auth header" do
    env = {
      "HTTP_AUTHORIZATION" => "token d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remove IP for authnd access token in auth header" do
    env = {
      "HTTP_AUTHORIZATION" => "token #{@fine_grained_pat}",
    }
    assert_equal "token:#{@fine_grained_pat_last_eight}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth username" do
    # username "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    # password "x"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f:x")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses token hash without ip for hashed_token serialization mode" do
    credentials = Base64.encode64("#{@fine_grained_pat}:x")

    env = {
      "HTTP_AUTHORIZATION" => "Basic #{credentials}",
    }
    assert_equal "token:#{@fine_grained_pat_hash}", fingerprint(env, token_serialization: :hashed_token).to_s

  end

  test "uses last eight and remote IP for authnd access token in basic auth username" do
    # username "github_pat_1..."
    # password "x"
    credentials = Base64.encode64("#{@fine_grained_pat}:x")

    env = {
      "HTTP_AUTHORIZATION" => "Basic #{credentials}",
    }
    assert_equal "token:#{@fine_grained_pat_last_eight}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth username and x-oauth-basic in password" do
    # username "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    # password "x-oauth-basic"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f:x-oauth-basic")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for authnd access token in basic auth username and x-oauth-basic in password" do
    # username "github_pat_1..."
    # password "x-oauth-basic"
    credentials = Base64.encode64("#{@fine_grained_pat}:x-oauth-basic")

    env = {
      "HTTP_AUTHORIZATION" => "Basic #{credentials}",
    }
    assert_equal "token:#{@fine_grained_pat_last_eight}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth password and signifier in username" do
    # username "x-oauth-basic"
    # password "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("x-oauth-basic:d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for authnd access token in basic auth password and signifier in username" do
    # username "x-oauth-basic"
    # password "github_pat_1..."
    credentials = Base64.encode64("x-oauth-basic:#{@fine_grained_pat}")

    env = {
      "HTTP_AUTHORIZATION" => "Basic #{credentials}",
    }
    assert_equal "token:#{@fine_grained_pat_last_eight}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth password with username signifier when feature flag enabled" do
    # username "defunkt"
    # password "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("defunkt:d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth password with invalid username signifier when feature flag enabled" do
    # username "defunkt@#!"
    # password "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("defunkt@#!:d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth password with non-hex 20-char username signifier when feature flag enabled" do
    # username "defunkt--is--defunkt"
    # password "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    username = "defunkt--is--defunkt"
    password = "b67a16914f77379a87026b667596e0acff7b9bad"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("#{username}:#{password}")}",
    }

    assert_equal 20, username.length
    assert_equal 40, password.length
    assert_equal "token:ff7b9bad:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in basic auth password with no username signifier when feature flag enabled" do
    # username ""
    # password "d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64(":d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f")}",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for authnd access token in basic auth password with no username signifier when feature flag enabled" do
    # username ""
    # password "github_pat_1..."
    credentials = Base64.encode64(":#{@fine_grained_pat}")

    env = {
      "HTTP_AUTHORIZATION" => "Basic #{credentials}",
    }
    assert_equal "token:#{@fine_grained_pat_last_eight}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses last eight and remote IP for access token in query string" do
    env = {
      "QUERY_STRING" => "page=2&per_page=100&access_token=d68b93a9922b8bbfd76d5c7bcf5b63f2aec8f36f",
    }
    assert_equal "token:aec8f36f:207.207.0.3", fingerprint(env).to_s
  end

  test "uses username and remote IP for user basic auth" do
    enable_feature_flag(:emu_basic_auth_fingerprint)
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("#{@user.display_login}:il0veruby")}",
    }
    assert_equal "user:#{@user.display_login}:207.207.0.3", fingerprint(env).to_s
  end


  test "uses remote IP for user basic auth" do
    disable_feature_flag(:emu_basic_auth_fingerprint)
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("#{@user.display_login}:il0veruby")}",
    }
    if TestEnv.test_with_all_emus?
      assert_equal "207.207.0.3", fingerprint(env).to_s
    else
      assert_equal "user:#{@user.display_login}:207.207.0.3", fingerprint(env).to_s
    end
  end

  test "uses username for user basic auth but omits IP address when omit_ip: true" do
    enable_feature_flag(:emu_basic_auth_fingerprint)
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("#{@user.display_login}:il0veruby")}",
    }
    assert_equal "user:#{@user.display_login}", fingerprint(env, omit_ip: true).to_s
  end

  test "uses remote IP if username doesn't conform for user basic auth" do
    # username "this isn't really a username -- #nope"
    # password "password"
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("this isn't really a username -- #nope:password")}",
    }
    assert_equal "207.207.0.3", fingerprint(env).to_s
  end

  test "uses app key and remote IP for app creds via basic auth" do
    # key    5367b366f4a982fbff5d
    # secret bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d
    env = {
      "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("5367b366f4a982fbff5d:bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d")}",
    }
    # app:<key>:<remote ip>"
    assert_equal "app:5367b366f4a982fbff5d:207.207.0.3", fingerprint(env).to_s
  end

  test "uses app key and remote IP for app creds via query string" do
    # key    5367b366f4a982fbff5d
    # secret bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d
    env = {
      "QUERY_STRING" => "page=2&per_page=100&client_id=5367b366f4a982fbff5d&client_secret=bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d",
    }
    assert_equal "app:5367b366f4a982fbff5d:207.207.0.3", fingerprint(env).to_s
  end

  test "uses app key for app creds via query string but omits IP address when omit_ip: true" do
    # key    5367b366f4a982fbff5d
    # secret bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d
    env = {
      "QUERY_STRING" => "page=2&per_page=100&client_id=5367b366f4a982fbff5d&client_secret=bc6ef1be491ce4ee0330f0af9b8b3a12ccc2373d",
    }
    assert_equal "app:5367b366f4a982fbff5d", fingerprint(env, omit_ip: true).to_s
  end

  test "uses the Integration ID and Remote IP for JWT auth when the feature flag is enabled" do
    integration = create(:integration)
    key = integration.generate_key(creator: integration.owner)
    rsa = key.private_key

    env = {
      "HTTP_AUTHORIZATION" => "Bearer #{ jwt(payload: jwt_payload(integration), rsa: rsa) }",
    }
    assert_equal "integration:#{integration.id}:207.207.0.3", fingerprint(env).to_s
  end

  test "uses the Integration ID for JWT auth but omits the IP address when omit_ip is true" do
    integration = create(:integration)
    key = integration.generate_key(creator: integration.owner)
    rsa = key.private_key

    env = {
      "HTTP_AUTHORIZATION" => "Bearer #{ jwt(payload: jwt_payload(integration), rsa: rsa) }",
    }
    assert_equal "integration:#{integration.id}", fingerprint(env, omit_ip: true).to_s
  end

  test "gracefully handles malformed basic request" do
    env = {
      "HTTP_AUTHORIZATION" => "basic =",
    }
    assert_equal "207.207.0.3", fingerprint(env).to_s

    env = {
      "HTTP_AUTHORIZATION" => nil,
    }
    assert_equal "207.207.0.3", fingerprint(env).to_s
  end

  test "raises on invalid serialization format" do
    assert_raises do
      Api::RequestAuthenticationFingerprint.from({}, token_serialization: :invalid)
    end
  end

  context "#personal_access_token?" do
    test "true for FG PAT" do
      credentials = Base64.encode64("#{@fine_grained_pat}:x-oauth-basic")
      env = {
        "HTTP_AUTHORIZATION" => "Basic #{credentials}",
      }
      assert fingerprint(env).personal_access_token?
    end

    test "false for unauthenticated" do
      refute fingerprint({}).personal_access_token?
    end

    test "false for username/password" do
      env = {
        "HTTP_AUTHORIZATION" => "Basic #{Base64.encode64("#{@user.display_login}:il0veruby")}",
      }
      refute fingerprint(env).personal_access_token?
    end

    test "false for legacy PAT" do
      access = create(:oauth_access, user: @user)
      token = access.reset_token
      credentials = Base64.encode64("#{token}:x-oauth-basic")

      env = {
        "HTTP_AUTHORIZATION" => "Basic #{credentials}",
      }
      refute fingerprint(env).personal_access_token?
    end

    test "false for app u2s token" do
      access = create :github_app_access
      token, _ = access.redeem
      credentials = Base64.encode64("#{token}:x-oauth-basic")

      env = {
        "HTTP_AUTHORIZATION" => "Basic #{credentials}",
      }
      refute fingerprint(env).personal_access_token?
    end

    test "false for app s2s token" do
      installation = make_integration_installation(target: create(:user))
      _, token = installation.generate_token
      credentials = Base64.encode64("#{token}:x-oauth-basic")

      env = {
        "HTTP_AUTHORIZATION" => "Basic #{credentials}",
      }
      refute fingerprint(env).personal_access_token?
    end
  end

  def fingerprint(options = {}, token_serialization: :default, omit_ip: false)
    env = {
      "REMOTE_ADDR" => "207.207.0.3",
    }.merge(options)

    Api::RequestAuthenticationFingerprint.from(env, token_serialization: token_serialization, omit_ip: omit_ip)
  end
end
