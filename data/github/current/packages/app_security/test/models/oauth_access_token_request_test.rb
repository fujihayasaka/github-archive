# typed: true
# frozen_string_literal: true

require "test_helper"

class OauthAccessTokenRequestTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @oauth_app = create(:oauth_application, device_flow_enabled: true)
    @plaintext_oauth_secret = @oauth_app.generate_client_secret(creator: @oauth_app.user).secret
    @access = create(:oauth_access, user: @user, application: @oauth_app, scopes: [:user, :repo])

    @integration = create(:integration,
      application_callback_urls_attributes: [{ url: "http://example.com/callback" }],
      device_flow_enabled: true,
      default_permissions: {
        "issues" => :write,
        "contents" => :read
      },
    )
    @plaintext_integration_secret = @integration.generate_client_secret(creator: @integration.user).secret
  end

  setup do
    @user.emails.first.verify!
  end

  context "errors" do
    test "malformed redirect_uri" do
      response = process(@oauth_app, code: "abc", client_secret: @plaintext_oauth_secret, redirect_uri: "http://yahtzee.com:bad_port/foo")
      expected_error_uri = "#{GitHub.developer_help_url}/apps/building-oauth-apps/authorization-options-for-oauth-apps/#redirect-urls"

      assert_equal :redirect_uri_invalid,                   response[:error]
      assert_equal "The redirect_uri MUST be a valid URL.", response[:error_description]
      assert_equal expected_error_uri,                      response[:error_uri]
    end

    test "malformed redirect_uri is instrumented" do
      process(@oauth_app, code: "abc", client_secret: @plaintext_oauth_secret, redirect_uri: "http://yahtzee.com:bad_port/foo")

      assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
    end

    context "incorrect_client_credentials" do
      test "client_secret is not provided" do
        response = process(@oauth_app, code: "abc")

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#incorrect-client-credentials"

        assert_equal :incorrect_client_credentials,                              response[:error]
        assert_equal "The client_id and/or client_secret passed are incorrect.", response[:error_description]
        assert_equal expected_error_uri,                                         response[:error_uri]

        assert_hydro_published_partial({ exchange_result: "INVALID_CLIENT_CREDENTIAL" }, schema: "github.v1.OauthExchange")
      end

      test "client_secret sent inside of an Array" do
        response = process(@oauth_app,
          code: "abc",
          client_secret: [@plaintext_oauth_secret]
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#incorrect-client-credentials"

        assert_equal :incorrect_client_credentials,                              response[:error]
        assert_equal "The client_id and/or client_secret passed are incorrect.", response[:error_description]
        assert_equal expected_error_uri,                                         response[:error_uri]

        assert_hydro_published_partial({ exchange_result: "INVALID_CLIENT_CREDENTIAL" }, schema: "github.v1.OauthExchange")
      end
    end

    context "redirect_uri_mismatch" do
      test "bad redirect_uri" do
        response = process(@oauth_app,
          code: "abc",
          client_secret: @plaintext_oauth_secret,
          redirect_uri: "http://foobar.com",
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"

        assert_equal :redirect_uri_mismatch,                                                          response[:error]
        assert_equal "The redirect_uri MUST match the registered callback URL for this application.", response[:error_description]
        assert_equal expected_error_uri,                                                              response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
      end

      test "given redirect_uri with bad slashes after scheme" do
        @access.grant("gist, repo")

        response = process(@oauth_app,
          code: @access.code,
          client_secret: @plaintext_oauth_secret,
          redirect_uri: "http:/localhost:5150", #single slash
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"

        assert_equal :redirect_uri_mismatch,                                                          response[:error]
        assert_equal "The redirect_uri MUST match the registered callback URL for this application.", response[:error_description]
        assert_equal expected_error_uri,                                                              response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
      end

      test "given redirect_uri with badly encoded hostname" do
        @access.grant("gist, repo")

        response = process(@oauth_app,
          code: @access.code,
          client_secret: @plaintext_oauth_secret,
          redirect_uri: "https://some_attacker_domain%2523.gist.github.com/auth/github/callback", # %2523 => #
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"

        assert_equal :redirect_uri_mismatch,                                                          response[:error]
        assert_equal "The redirect_uri MUST match the registered callback URL for this application.", response[:error_description]
        assert_equal expected_error_uri,                                                              response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
      end

      test "redirect_uri as a Hash does not raise an exception" do
        create(:application_callback_url, application: @integration, url: "https://admin.example.com/callback")
        @integration.reload

        access = @integration.grant(@user)

        assert_predicate @integration, :strict_callback_url_validation?

        response = process(@integration,
          code: access.code,
          client_secret: @plaintext_integration_secret,
          redirect_uri: { "$acunetix" => "[FILTERED]" },
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"

        assert_equal :redirect_uri_mismatch,                                                          response[:error]
        assert_equal "The redirect_uri MUST match the registered callback URL for this application.", response[:error_description]
        assert_equal expected_error_uri,                                                              response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
      end

      test "redirect_uri does not match requested redirect uri with code_exchange_redirect_uri_compare enabled" do
        GitHub.flipper[:code_exchange_redirect_uri_compare].enable
        redirect = "http://example.com/callback"

        access = @integration.grant(@user, redirect_uri: redirect)

        response = process(@integration,
          code: access.code,
          client_secret: @plaintext_integration_secret,
          redirect_uri: "http://sub.example.com/callback",
        )

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"

        assert_equal :redirect_uri_mismatch,                                                        response[:error]
        assert_equal "The redirect_uri MUST match the callback URL provided during authorization.", response[:error_description]
        assert_equal expected_error_uri,                                                            response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
      end

      test "redirect_uri does not match requested redirect uri with code_exchange_redirect_uri_compare enabled instruments result" do
        GitHub.flipper[:code_exchange_redirect_uri_compare].enable
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)
        redirect = "http://example.com/callback"

        access = @integration.grant(@user, redirect_uri: redirect)

        process(@integration,
          code: access.code,
          client_secret: @plaintext_integration_secret,
          redirect_uri: "http://sub.example.com/callback",
        )

        assert_equal 1, stats.increments("oauth_access_token_request.redirect_uri_validation").length, "expected a validation event"
        assert_same_elements ["result:mismatch"], stats.increments("oauth_access_token_request.redirect_uri_validation").first.tags
      end

      test "redirect_uri does not match requested redirect uri with code_exchange_redirect_uri_compare enabled for single application" do
        GitHub.flipper[:code_exchange_redirect_uri_compare].enable(@oauth_app)
        stats = GitHub::MemoryDogstatsD.new
        GitHub.stubs(:dogstats).returns(stats)
        redirect = "http://example.com/callback"

        access = @oauth_app.grant(@user, redirect_uri: redirect)

        response = process(@oauth_app,
          code: access.code,
          client_secret: @plaintext_integration_secret,
          redirect_uri: "http://sub.example.com/callback",
        )

        assert_equal :redirect_uri_mismatch,                                                        response[:error]
        assert_equal "The redirect_uri MUST match the callback URL provided during authorization.", response[:error_description]
        assert_hydro_published_partial({ exchange_result: "INVALID_REDIRECT_URI" }, schema: "github.v1.OauthExchange")
        assert_equal 1, stats.increments("oauth_access_token_request.redirect_uri_validation").length, "expected a validation event"
        assert_same_elements ["result:mismatch"], stats.increments("oauth_access_token_request.redirect_uri_validation").first.tags
      end

      test "redirect_uri does not match requested redirect uri with code_exchange_redirect_uri_compare disabled" do
        GitHub.flipper[:code_exchange_redirect_uri_compare].disable
        redirect = "http://example.com/callback"

        access = @integration.grant(@user, redirect_uri: redirect)

        response = process(@integration,
          code: access.code,
          client_secret: @plaintext_integration_secret,
          redirect_uri: "http://sub.example.com/callback",
        )

        assert_nil response[:error]
      end
    end

    context "bad_verification_code" do
      test "missing code" do
        response = process(@oauth_app, code: "abc", client_secret: @plaintext_oauth_secret)
        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"

        assert_equal :bad_verification_code,                     response[:error]
        assert_equal "The code passed is incorrect or expired.", response[:error_description]
        assert_equal expected_error_uri,                         response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_CODE" }, schema: "github.v1.OauthExchange")
      end

      test "when given integer OauthAccess#code" do
        response = process(@oauth_app, code: 0, client_secret: @plaintext_oauth_secret)
        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"

        assert_equal :bad_verification_code,                     response[:error]
        assert_equal "The code passed is incorrect or expired.", response[:error_description]
        assert_equal expected_error_uri,                         response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_CODE" }, schema: "github.v1.OauthExchange")
      end

      test "when two clients try to redeem the same code too quickly" do
        @integration.update!(user_token_expiration: true)

        access = @integration.grant(@user)
        code = access.code

        response = process(@integration, code: code, client_secret: @plaintext_integration_secret)
        access.reload

        assert_hydro_published_partial({
          token_last_eight: response[:access_token][-8..-1],
          refresh_token_last_eight: response[:refresh_token][-8..-1],
          exchange_result: "SUCCESS"
        }, schema: "github.v1.OauthExchange")

        access.update(code: code); access.reload

        # Simulate the race condition by just stubbing the exception seen in
        # Sentry https://github.com/github/ecosystem-apps/issues/1716#issuecomment-960178773
        OauthAccess.any_instance.stubs(:redeem).raises(ActiveRecord::RecordNotUnique)
        response = process(@integration, code: code, client_secret: @plaintext_integration_secret)

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"

        assert_equal :bad_verification_code,                     response[:error]
        assert_equal "The code passed is incorrect or expired.", response[:error_description]
        assert_equal expected_error_uri,                         response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_CODE" }, schema: "github.v1.OauthExchange")
      end
    end

    context "device authorization" do
      test "record could not be found" do
        response = process(@oauth_app, device_code: "ABCD-1234", grant_type: DeviceAuthorizationGrant::GRANT_TYPE)
        expected_error_uri = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"

        assert_equal :incorrect_device_code,                   response[:error]
        assert_equal "The device_code provided is not valid.", response[:error_description]
        assert_equal expected_error_uri,                       response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "INVALID_DEVICE_CODE" }, schema: "github.v1.OauthExchange")
      end

      test "access was denied" do
        device_grant = create(:device_authorization_grant, application: @oauth_app)
        device_code = device_grant.redeem_device_code!

        device_grant.update(access_denied: true)
        response = process(@oauth_app, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)

        expected_error_uri = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"

        assert_equal :access_denied,                          response[:error]
        assert_equal "The authorization request was denied.", response[:error_description]
        assert_equal expected_error_uri,                      response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "DEVICE_AUTHORIZATION_DENIED" }, schema: "github.v1.OauthExchange")
      end

      test "expired_token" do
        Timecop.freeze do
          device_grant = create(:device_authorization_grant, application: @oauth_app)
          device_code = device_grant.redeem_device_code!

          expected_error_uri = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"

          Timecop.travel(15.minutes.from_now) do
            response = process(@oauth_app, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)

            assert_equal :expired_token,                    response[:error]
            assert_equal "This 'device_code' has expired.", response[:error_description]
            assert_equal expected_error_uri,                response[:error_uri]
            assert_hydro_published_partial({ exchange_result: "DEVICE_CODE_EXPIRED" }, schema: "github.v1.OauthExchange")
          end
        end
      end

      test "unauthorized" do
        device_grant = create(:device_authorization_grant, application: @oauth_app)
        device_code = device_grant.redeem_device_code!

        response = process(@oauth_app, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)
        expected_error_uri = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"

        assert_equal :authorization_pending,                        response[:error]
        assert_equal "The authorization request is still pending.", response[:error_description]
        assert_equal expected_error_uri,                            response[:error_uri]
        assert_hydro_messages(count: 0, schema: "github.v1.OauthExchange")
      end

      test "device flow disabled" do
        oauth_app = create(:oauth_application, device_flow_enabled: false)
        device_grant = create(:device_authorization_grant, application: oauth_app)
        device_code = device_grant.redeem_device_code!

        response = process(oauth_app, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)

        expected_error_uri = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"

        assert_equal :device_flow_disabled,                                                 response[:error]
        assert_equal "This application has not enabled authorization via the device flow.", response[:error_description]
        assert_equal expected_error_uri,                                                    response[:error_uri]
        assert_hydro_published_partial({ exchange_result: "DEVICE_FLOW_DISABLED" }, schema: "github.v1.OauthExchange")
      end
    end

    context "unverified_user_email" do
      test "user email is not verified", skip_enterprise: true do
        @user.emails.first.unverify!

        @access.grant("gist, repo")
        response = process(@oauth_app, code: @access.code, client_secret: @plaintext_oauth_secret)

        expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#incorrect-client-credentials"

        assert_equal :unverified_user_email,                response[:error]
        assert_equal "The user must have a verified primary email", response[:error_description]
        assert_equal expected_error_uri,                    response[:error_uri]

        assert_hydro_published_partial({ exchange_result: "INVALID_USER_EMAIL" }, schema: "github.v1.OauthExchange")
      end
    end
  end

  context "refresh tokens" do
    test "doesn't send refresh_token if flag is disabled" do
      @integration.update!(user_token_expiration: false)
      access = @integration.grant(@user)

      response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)

      refute response.has_key?(:expires_in)
      refute response.has_key?(:refresh_token)
      refute response.has_key?(:refresh_token_expires_in)
      assert_hydro_published_partial({
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: nil,
        exchange_result: "SUCCESS"
      }, schema: "github.v1.OauthExchange")
    end

    test "returns a refresh token when flag is enabled" do
      @integration.update!(user_token_expiration: false)

      access = @integration.grant(@user)
      response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)

      refute_nil response[:access_token]
      refute response.has_key?(:refresh_token)

      @integration.update!(user_token_expiration: true)

      access = @integration.grant(@user)
      response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)

      refute_predicate response[:refresh_token], :empty?
      assert_hydro_published_partial({
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: response[:refresh_token][-8..-1],
        exchange_result: "SUCCESS"
      }, schema: "github.v1.OauthExchange")
    end

    test "resets an access token when passed a refresh token and secret" do
      access = @integration.grant(@user)
      original_token, original_refresh = access.redeem

      response = process(@integration,
        client_secret: @plaintext_integration_secret,
        grant_type: "refresh_token",
        refresh_token: original_refresh,
      )

      refute_nil response[:access_token]
      refute_nil response[:expires_in]
      refute_nil response[:refresh_token]
      refute_nil response[:refresh_token_expires_in]

      refute_equal original_token, response[:access_token]
      refute_equal original_refresh, response[:refresh_token]

      refute_predicate response[:refresh_token], :empty?

      assert_hydro_published_partial({
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: response[:refresh_token][-8..-1],
        exchanged_refresh_token_last_eight: original_refresh[-8..-1],
        exchange_result: "SUCCESS"
      }, schema: "github.v1.OauthExchange")
    end

    test "requires grant type refresh token param" do
      access = @integration.grant(@user)
      _original_token, original_refresh = access.redeem

      response = process(@integration,
        client_secret: @plaintext_integration_secret,
        refresh_token: original_refresh,
      )

      assert_hydro_published_partial({ exchange_result: "UNSUPPORTED_GRANT_TYPE" }, schema: "github.v1.OauthExchange")
      assert_equal :unsupported_grant_type, response[:error]

      assert_nil response[:access_token]
      assert_nil response[:expires_in]
      assert_nil response[:refresh_token]
      assert_nil response[:refresh_token_expires_in]
    end

    test "sends refresh_token_expires_in and expires_in as an int" do
      access = @integration.grant(@user)
      _original_token, original_refresh = access.redeem

      response = process(@integration,
        client_secret: @plaintext_integration_secret,
        grant_type: "refresh_token",
        refresh_token: original_refresh,
      )

      assert_equal response[:expires_in].to_i, OauthAccess::DEFAULT_INSTALLATION_TOKEN_EXPIRY.to_i
      assert_match %r(\d{3,}), response[:refresh_token_expires_in].to_s

      assert_hydro_published_partial({
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: response[:refresh_token][-8..-1],
        exchanged_refresh_token_last_eight: original_refresh[-8..-1],
        exchange_result: "SUCCESS"
      }, schema: "github.v1.OauthExchange")
    end

    test "returns incorrect credentials passed a refresh token and invalid secret" do
      @integration.update!(user_token_expiration: true)

      access = @integration.grant(@user)
      _original_token, original_refresh = access.redeem

      response = process(@integration,
        client_secret: "supersecretthing",
        grant_type: "refresh_token",
        refresh_token: original_refresh,
      )

      expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#incorrect-client-credentials"

      assert_same_hash({
        error: :incorrect_client_credentials,
        error_description: "The client_id and/or client_secret passed are incorrect.",
        error_uri: expected_error_uri,
      }, response)

      assert_hydro_published_partial({ exchange_result: "INVALID_CLIENT_CREDENTIAL" }, schema: "github.v1.OauthExchange")
    end

    test "returns incorrect credentials passed an invalid refresh token" do
      access = @integration.grant(@user)
      _original_token, _original_refresh = access.redeem

      response = process(@integration,
        client_secret: @plaintext_integration_secret,
        grant_type: "refresh_token",
        refresh_token: "supersecretthing",
      )

      expected_error_uri = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"

      assert_same_hash({
        error: :bad_refresh_token,
        error_description: "The refresh token passed is incorrect or expired.",
        error_uri: expected_error_uri,
      }, response)

      assert_hydro_published_partial({
        exchanged_refresh_token_last_eight: "retthing",
        exchange_result: "REFRESH_TOKEN_NOT_FOUND"
      }, schema: "github.v1.OauthExchange")
    end

    test "does not require the client_secret if the token was created via the device flow" do
      device_authorization_grant = create(:device_authorization_grant, application: @integration)

      access = @integration.grant(@user)
      device_authorization_grant.update(oauth_access: access); access.reload

      original_token, original_refresh = access.redeem

      response = process(@integration, grant_type: "refresh_token", refresh_token: original_refresh)

      refute_nil response[:access_token]
      refute_nil response[:expires_in]
      refute_nil response[:refresh_token]
      refute_nil response[:refresh_token_expires_in]

      refute_equal original_token, response[:access_token]
      refute_equal original_refresh, response[:refresh_token]

      refute_predicate response[:refresh_token], :empty?

      assert_hydro_published_partial({
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: response[:refresh_token][-8..-1],
        exchanged_refresh_token_last_eight: original_refresh[-8..-1],
        exchange_result: "SUCCESS"
      }, schema: "github.v1.OauthExchange")
    end

    test "supports 'refresh_token' parameter serialized as a boolean" do
      access = @integration.grant(@user)
      access.redeem

      response = process(@integration,
        client_secret: @plaintext_integration_secret,
        refresh_token: false
      )

      assert_equal :unsupported_grant_type, response[:error]

      assert_nil response[:access_token]
      assert_nil response[:expires_in]
      assert_nil response[:refresh_token]
      assert_nil response[:refresh_token_expires_in]

      assert_hydro_published_partial({ exchange_result: "UNSUPPORTED_GRANT_TYPE" }, schema: "github.v1.OauthExchange")
    end
  end

  context "oauth accesses" do
    test "succeeds" do
      @access.grant("gist, repo")

      response = process(@oauth_app, code: @access.code, client_secret: @plaintext_oauth_secret)
      @access.reload

      assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "gist,repo" }, response)
      assert_token_exchanged(response[:access_token])
      assert_hydro_published_partial({ exchange_result: "SUCCESS" }, schema: "github.v1.OauthExchange")
    end

    test "updates accessed_at for an oauth app" do
      @access.grant("gist, repo")

      client_secret = @oauth_app.client_secrets.first

      assert_nil client_secret.accessed_at

      perform_enqueued_jobs(only: [OauthApplicationClientSecretAccessJob]) do
        Timecop.freeze(Time.zone.now) do
          response = process(@oauth_app, code: @access.code, client_secret: @plaintext_oauth_secret)

          @access.reload
          client_secret.reload

          assert_equal Time.zone.now.to_i, client_secret.accessed_at.to_i
          assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "gist,repo" }, response)
          assert_token_exchanged(response[:access_token])
        end
      end
    end

    test "succeeds for an integration" do
      @integration.update!(user_token_expiration: false)
      access = @integration.grant(@user)

      response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)
      access.reload

      assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "" }, response)
      assert_token_exchanged(response[:access_token], access)
      assert_hydro_published_partial({ exchange_result: "SUCCESS" }, schema: "github.v1.OauthExchange")
    end

    test "updates accessed_at for an integration" do
      client_secret = @integration.client_secrets.first
      assert_nil client_secret.accessed_at

      @integration.update!(user_token_expiration: false)
      access = @integration.grant(@user)

      perform_enqueued_jobs(only: [IntegrationClientSecretAccessJob]) do
        Timecop.freeze(Time.zone.now) do
          response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)

          access.reload
          client_secret.reload

          assert_equal Time.zone.now.to_i, client_secret.accessed_at.to_i
          assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "" }, response)
          assert_token_exchanged(response[:access_token], access)
        end
      end
    end

    context "device authorization grants" do
      test "succeeds" do
        device_grant = create(:device_authorization_grant, application: @oauth_app)
        device_code = device_grant.redeem_device_code!

        @access = @oauth_app.grant(create(:user), scope: "repo")
        @access.user.emails.first.verify!
        device_grant.update(oauth_access: @access)

        response = process(@oauth_app, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)
        @access.reload

        assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "repo" }, response)
        assert_token_exchanged(response[:access_token])
        assert_hydro_published_partial({ exchange_result: "SUCCESS" }, schema: "github.v1.OauthExchange")
      end

      test "succeeds for an integration" do
        @integration.update!(user_token_expiration: false)

        device_grant = create(:device_authorization_grant, application: @integration)
        device_code = device_grant.redeem_device_code!

        @access = @integration.grant(create(:user))
        @access.user.emails.first.verify!
        device_grant.update(oauth_access: @access)

        response = process(@integration, device_code: device_code, grant_type: DeviceAuthorizationGrant::GRANT_TYPE)
        @access.reload

        assert_same_hash({ access_token: response[:access_token], token_type: :bearer, scope: "" }, response)
        assert_token_exchanged(response[:access_token])
        assert_hydro_published_partial({ exchange_result: "SUCCESS" }, schema: "github.v1.OauthExchange")
      end
    end

    context "scoped user-to-server tokens" do
      test "creates a ScopedIntegrationInstallation record" do
        repo = create(:repository, :minimal, owner: @user)

        integration = create(:integration, default_permissions: { "metadata" => :read })
        integration.update(user_token_expiration: false); integration.reload

        create(:application_callback_url, application: integration, url: "https://example.com/")
        secret = integration.generate_client_secret(creator: @user).secret

        make_integration_installation(integration: integration, target: @user)

        access = integration.grant(@user)
        expected_token = access.reset_token
        expected_hash = OauthAccess.hash_token(expected_token)

        OauthAccess.any_instance.stubs(:generate_random_token_pair).returns([expected_token, expected_hash])

        response = process(integration,
          code: access.code,
          client_secret: secret,
          repository_id: repo.id
        )

        access.reload

        assert_same_hash({
          access_token: expected_token,
          token_type: :bearer,
          scope: "",
          repos_url: ::Api::Serializer.url("/user/repos"),
          permissions: { "metadata" => :read },
        }, response)

        assert_hydro_published_partial({ exchange_result: "SUCCESS" }, schema: "github.v1.OauthExchange")
      end

      test "fails when a repo is not provided and is required" do
        integration = create_privileged_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens_required: true })
        create(:application_callback_url, application: integration, url: "https://example.com/")
        secret = integration.generate_client_secret(creator: @user).secret

        access = integration.grant(@user)

        response = process(integration,
          code: access.code,
          client_secret: secret,
        )

        assert_equal :missing_repository,                                                                  response[:error]
        assert_equal "This application requires that a repository is provided to redeem the OAuth token.", response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/",                      response[:error_uri]

        assert_hydro_published_partial({ exchange_result: "INTERNAL_APP_FAILURE" }, schema: "github.v1.OauthExchange")
      end

      test "fails when a private repo the user can't see is passed" do
        repo = create(:private_repository, :minimal)

        integration = create(:integration, default_permissions: { "metadata" => :read })
        create(:application_callback_url, application: integration, url: "https://example.com/")
        secret = integration.generate_client_secret(creator: @user).secret

        access = integration.grant(@user)

        response = process(integration,
          code: access.code,
          client_secret: secret,
          repository_id: repo.id
        )

        assert_equal :repository_not_found,                                           response[:error]
        assert_equal "The repository requested could not be found.",                  response[:error_description]
        assert_equal "https://thehub.github.com/engineering/development-and-ops/dotcom/apps/github-apps/internal-apps/", response[:error_uri]

        assert_hydro_published_partial({ exchange_result: "INTERNAL_APP_FAILURE" }, schema: "github.v1.OauthExchange")
      end
    end

    context "automatic app installations" do
      test "installs the app if it has the :oauth_code_exchange trigger and is enabled" do
        register_internal_app(@integration, { can_auto_install_apps_on_oauth_code_exchanged: true })
        create(:integration_install_trigger, integration: @integration, install_type: :oauth_code_exchanged)

        access = @integration.grant(@user)
        refute @integration.installed_on?(@user)

        response = perform_enqueued_jobs(only: [InstallAutomaticIntegrationsJob]) do
          process(@integration, code: access.code, client_secret: @plaintext_integration_secret)
        end

        refute_nil response[:access_token]
        assert @integration.installed_on?(@user)
      end

      test "does not perform installations on apps with the :oauth_code_exchange trigger when they are not enabled" do
        refute Apps::Privileged.capable?(:can_auto_install_apps_on_oauth_code_exchanged, app: @integration)
        create(:integration_install_trigger, integration: @integration, install_type: :oauth_code_exchanged)

        access = @integration.grant(@user)

        AutomaticAppInstallation.expects(:trigger).never
        process(@integration, code: access.code, client_secret: @plaintext_integration_secret)
      end

      test "does not perform installations on other applications" do
        dummy_integration = create(:integration)

        register_internal_app(dummy_integration, { can_auto_install_apps_on_oauth_code_exchanged: true })
        register_internal_app(@integration, { can_auto_install_apps_on_oauth_code_exchanged: true })

        create(:integration_install_trigger, integration: dummy_integration, install_type: :oauth_code_exchanged)

        access = @integration.grant(@user)

        refute @integration.installed_on?(@user)
        refute dummy_integration.installed_on?(@user)

        response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)

        refute_nil response[:access_token]
        refute @integration.installed_on?(@user)
        refute dummy_integration.installed_on?(@user)
      end

      test "doesn't trigger installations on failed code exchanges" do
        register_internal_app(@integration, { can_auto_install_apps_on_oauth_code_exchanged: true })
        create(:integration_install_trigger, integration: @integration, install_type: :oauth_code_exchanged)

        refute @integration.installed_on?(@user)

        AutomaticAppInstallation.expects(:trigger).never
        response = process(@integration, code: "fake-token", client_secret: @plaintext_integration_secret)

        assert_nil response[:access_token]
        refute_nil response[:error]
      end

      test "does not trigger installations on refresh token flows" do
        access = @integration.grant(@user)
        _, original_refresh = access.redeem

        create(:integration_install_trigger, integration: @integration, install_type: :oauth_code_exchanged)

        AutomaticAppInstallation.expects(:trigger).never
        response = process(@integration,
          client_secret: @plaintext_integration_secret,
          grant_type: "refresh_token",
          refresh_token: original_refresh,
        )

        refute_nil response[:access_token]
      end

      test "doesn't trigger installations on OAuth Apps flows"  do
        @access.grant("gist, repo")

        AutomaticAppInstallation.expects(:trigger).never
        response = process(@oauth_app, code: @access.code, client_secret: @plaintext_oauth_secret)

        refute_nil response[:access_token]
      end
    end
  end

  context "hydro message publication" do
    test "succeeds for an integration" do
      access = @integration.grant(@user)

      response = process(@integration, code: access.code, client_secret: @plaintext_integration_secret)
      access.reload

      assert_token_exchanged(response[:access_token], access)
      assert_hydro_published({
        request_context: nil,
        database_id: access.id,
        app_type: :INTEGRATION,
        oauth_application: nil,
        integration: Hydro::EntitySerializer.integration(@integration),
        exchange_result: "SUCCESS",
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: response[:refresh_token][-8..-1],
        exchanged_refresh_token_last_eight: nil,
      }, schema: "github.v1.OauthExchange")
    end

    test "succeeds for an oauth app" do
      access = @oauth_app.grant(@user)

      response = process(@oauth_app, code: access.code, client_secret: @plaintext_oauth_secret)
      access.reload

      assert_token_exchanged(response[:access_token], access)
      assert_hydro_published({
        request_context: nil,
        database_id: access.id,
        app_type: :OAUTH_APPLICATION,
        integration: nil,
        oauth_application: Hydro::EntitySerializer.oauth_application(@oauth_app),
        exchange_result: "SUCCESS",
        token_last_eight: response[:access_token][-8..-1],
        refresh_token_last_eight: nil,
        exchanged_refresh_token_last_eight: nil,
      }, schema: "github.v1.OauthExchange")
    end

    test "failure messages contain app information for oauth apps" do
      @access.grant("gist, repo")

      process(@oauth_app,
        code: @access.code,
        client_secret: @plaintext_oauth_secret,
        redirect_uri: "https://some_attacker_domain%2523.gist.github.com/auth/github/callback", # %2523 => #
      )

      assert_hydro_published({
        request_context: nil,
        database_id: @access.id,
        app_type: :OAUTH_APPLICATION,
        integration: nil,
        oauth_application: Hydro::EntitySerializer.oauth_application(@oauth_app),
        exchange_result: "INVALID_REDIRECT_URI",
        token_last_eight: nil,
        refresh_token_last_eight: nil,
        exchanged_refresh_token_last_eight: nil,
      }, schema: "github.v1.OauthExchange")
    end

    test "failure messages contain app information for internal apps" do
      integration = create_privileged_app_with_capabilities(capabilities: { per_repo_user_to_server_tokens_required: true })
      create(:application_callback_url, application: integration, url: "https://example.com/")
      secret = integration.generate_client_secret(creator: @user).secret

      access = integration.grant(@user)

      process(integration,
        code: access.code,
        client_secret: secret,
      )

      assert_hydro_published({
        request_context: nil,
        database_id: access.id,
        app_type: :INTEGRATION,
        oauth_application: nil,
        integration: Hydro::EntitySerializer.integration(integration),
        exchange_result: "INTERNAL_APP_FAILURE",
        token_last_eight: nil,
        refresh_token_last_eight: nil,
        exchanged_refresh_token_last_eight: nil,
      }, schema: "github.v1.OauthExchange")
    end
  end

  private

  def assert_token_exchanged(received_token, expected = @access)
    assert_equal expected.hashed_token, OauthAccess.hash_token(received_token)
    received = T.must(OauthAccess.find_by(hashed_token: OauthAccess.hash_token(received_token)))

    assert_equal expected.hashed_token,     received.hashed_token
    assert_equal expected.token_last_eight, received.token_last_eight

    assert_nil received.code
  end

  def process(application, **params)
    log_data = GitHub::Logger.empty
    params   = ActionController::Parameters.new(params)

    OauthAccessTokenRequest.process(application, log_data, params, entry_point: :test_case)
  end

  def register_internal_app(app, capabilities = {})
    Apps::Privileged::Registry.configure(
      app: app,
      type: app.class.to_s,
      app_alias: :"some_capable_app_#{SecureRandom.hex(6)}",
      id: ->() { app.id },
      capabilities: capabilities
    )
  end
end
