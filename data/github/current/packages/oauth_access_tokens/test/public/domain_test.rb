# typed: true
# frozen_string_literal: true

require "test_helper"

module OauthAccessTokens
  class DomainTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @oauth_application = create(:oauth_application, user: @user)
      @integration = create(:integration, user_token_expiration_enabled: true)

      @installation = make_scoped_integration_installation(
        parent: make_integration_installation(integration: @integration, target: @user),
        repositories: []
      )

      @oauth_access = create(:oauth_access, user: @user, application: @oauth_application)
      @oauth_access.reset_token # Ensure there's a hashed token available
      # Touch accessed_at so we can compare it
      @oauth_access.update!(accessed_at: Time.current)
      @personal_token = create(:personal_token_oauth_access, user: @user)
      @personal_token.update!(accessed_at: Time.current)
    end

    context ".token_regex" do
      test "matches valid OAuth tokens" do
        oauth_token = "gho_#{SecureRandom.alphanumeric(OauthAccess::TOKEN_LENGTH)}"
        assert_match Domain.token_regex, oauth_token
      end

      test "matches valid Personal Access Tokens" do
        pat_token = "ghp_#{SecureRandom.alphanumeric(OauthAccess::TOKEN_LENGTH)}"
        assert_match Domain.token_regex, pat_token
      end

      test "matches valid User-to-server tokens" do
        u2s_token = "ghu_#{SecureRandom.alphanumeric(OauthAccess::TOKEN_LENGTH)}"
        assert_match Domain.token_regex, u2s_token
      end

      test "does not match legacy tokens with regex" do
        legacy_token = SecureRandom.hex(20)
        refute_match Domain.token_regex, legacy_token
      end

      test "matches legacy tokens with legacy pattern" do
        legacy_token = SecureRandom.hex(20)
        assert_match Domain::TOKEN_LEGACY_PATTERN, legacy_token
      end
    end

    context ".normalize_scopes" do
      test "normalizes string scopes" do
        assert_equal %w[repo user], Domain.normalize_scopes("repo,user")
      end

      test "normalizes array scopes" do
        assert_equal %w[repo user], Domain.normalize_scopes(%w[repo user])
      end

      test "removes duplicates" do
        assert_equal %w[repo user], Domain.normalize_scopes("repo,user,repo")
      end

      test "handles empty inputs" do
        assert_equal [], Domain.normalize_scopes(nil)
        assert_equal [], Domain.normalize_scopes("")
      end
    end

    context ".invalid_scopes" do
      test "returns scopes that are not valid" do
        scopes = %w[repo user invalid_scope]
        assert_equal ["invalid_scope"], Domain.invalid_scopes(scopes)
      end
    end

    context ".matches_pattern?" do
      test "returns true for OAuth tokens" do
        oauth_token = "gho_#{SecureRandom.alphanumeric(OauthAccess::TOKEN_LENGTH)}"
        assert Domain.matches_pattern?(oauth_token)
      end

      test "returns true for legacy tokens" do
        legacy_token = SecureRandom.hex(20)
        assert Domain.matches_pattern?(legacy_token)
      end

      test "returns false for invalid tokens" do
        invalid_token = "invalid_token"
        refute Domain.matches_pattern?(invalid_token)
      end
    end

    context ".hash_token" do
      test "hashes tokens consistently" do
        token = "test_token"
        hashed1 = Domain.hash_token(token)
        hashed2 = Domain.hash_token(token)

        assert_equal hashed1, hashed2
        assert_equal OauthAccess.hash_token(token), hashed1
        assert_match OauthAccess::HASHED_TOKEN_PATTERN, hashed1
      end
    end

    context "#by_id" do
      test "returns the oauth access with the matching ID" do
        result = OauthAccessTokens.domain.by_id(@oauth_access.id)
        assert_equal @oauth_access.id, result&.id
        assert_kind_of IOauthAccess, result
      end

      test "returns nil for non-existent IDs" do
        result = OauthAccessTokens.domain.by_id(999999)
        assert_nil result
      end
    end

    context "#by_ids" do
      test "returns oauth accesses with the matching IDs" do
        results = OauthAccessTokens.domain.by_ids([@oauth_access.id, @personal_token.id])
        assert_equal 2, results.size
        assert_equal [@oauth_access.id, @personal_token.id].sort, results.map(&:id).sort
      end

      test "returns empty array for non-existent IDs" do
        results = OauthAccessTokens.domain.by_ids([999999])
        assert_empty results
      end
    end

    context "#by_hash" do
      test "returns oauth access with the matching hash" do
        hash = @oauth_access.hashed_token
        refute_nil hash, "OAuth access must have a hashed token for this test"

        result = OauthAccessTokens.domain.by_hash(hash)
        assert_equal @oauth_access.id, result&.id
      end

      test "returns nil for non-existent hash" do
        result = OauthAccessTokens.domain.by_hash("non_existent_hash")
        assert_nil result
      end
    end

    context "#by_user_and_hash" do
      test "returns oauth access with the matching user and hash" do
        hash = @oauth_access.hashed_token
        refute_nil hash, "OAuth access must have a hashed token for this test"

        result = OauthAccessTokens.domain.user_access_by_hash(@user.id, hash)
        assert_equal @oauth_access.id, result&.id
      end

      test "returns nil for non-existent user or hash" do
        hash = @oauth_access.hashed_token
        refute_nil hash, "OAuth access must have a hashed token for this test"

        result = OauthAccessTokens.domain.user_access_by_hash(999999, hash)
        assert_nil result

        result = OauthAccessTokens.domain.user_access_by_hash(@user.id, "non_existent_hash")
        assert_nil result
      end
    end

    context "#active" do
      test "returns oauth access for valid unhashed token" do
        token = @oauth_access.reset_token
        result = OauthAccessTokens.domain.active(token)
        assert_equal @oauth_access.id, result&.id
      end

      test "returns oauth access for valid hashed token when hashed parameter is true" do
        hash = @oauth_access.hashed_token
        refute_nil hash, "OAuth access must have a hashed token for this test"

        result = OauthAccessTokens.domain.active(hash, hashed: true)
        assert_equal @oauth_access.id, result&.id
      end

      test "returns nil if token is expired" do
        integration = create(:integration)

        access = integration.grant(@user)
        token, _refresh_token = access.redeem

        access.update!(expires_at: 0)

        result = OauthAccessTokens.domain.active(token)
        assert_nil result
      end

      test "returns nil for invalid token" do
        result = OauthAccessTokens.domain.active("invalid_token")
        assert_nil result
      end

      test "returns nil for non-string tokens" do
        result = OauthAccessTokens.domain.active(nil)
        assert_nil result

        result = OauthAccessTokens.domain.active(123)
        assert_nil result
      end
    end

    context "#personal_token_ids" do
      test "returns IDs of personal tokens for a user" do
        results = OauthAccessTokens.domain.personal_token_ids(@user.id)
        assert_includes results, @personal_token.id
        refute_includes results, @oauth_access.id
      end

      test "returns empty array for user with no personal tokens" do
        other_user = create(:user)
        results = OauthAccessTokens.domain.personal_token_ids(other_user.id)
        assert_empty results
      end
    end

    context "#installation_ids_with_accesses" do
      test "returns IDs of installations that have OAuth accesses" do
        app_access = create(:oauth_access, user: @user, application: @integration, installation: @installation)
        results = OauthAccessTokens.domain.installation_ids_with_accesses([@installation.id], "ScopedIntegrationInstallation")
        assert_includes results, @installation.id
      end

      test "returns empty array for installations without OAuth accesses" do
        other_installation = make_scoped_integration_installation(
          parent: make_integration_installation(integration: create(:integration), target: create(:user)),
          repositories: []
        )
        results = OauthAccessTokens.domain.installation_ids_with_accesses([other_installation.id], "ScopedIntegrationInstallation")
        assert_empty results
      end
    end

    context ".instrument_email_verification_required" do
      test "logs information and sends metrics" do
        GitHub.dogstats.expects(:increment).with("oauth_access", has_entry(:tags, ["action:email-verification", "valid:false", "user_signup_timeframe:#{@user.signup_timeframe}"]))
        GitHub.logger.expects(:info).with(has_entries(
          "gh.oauth_application.id" => @oauth_application.id,
          "enduser.id" => @user.login,
          "code.function" => "owner_meets_email_verification_requirements",
          "http.status_code" => "email_verification_required"
        ))

        Domain.instrument_email_verification_required(user: @user, application_id: @oauth_application.id)
      end
    end

    context "IOauthAccess interface" do
      test "interface includes all necessary methods" do
        # Get an IOauthAccess instance from the domain
        access = OauthAccessTokens.domain.by_id(@oauth_access.id)
        refute_nil access, "Access should not be nil"
        access = T.must(access)

        # Test key properties and methods on the interface
        assert_equal @oauth_access.id, access.id
        assert_equal @oauth_access.user_id, access.user_id
        assert_equal @oauth_access.user.id, access.user&.id
        assert_equal @oauth_access.application.id, access.application&.id
        assert_equal @oauth_access.oauth_application&.id, access.oauth_application&.id
        assert_equal @oauth_access.hashed_token, access.hashed_token
        assert_equal @oauth_access.code, access.code
        assert_equal @oauth_access.description, access.description
        assert_equal @oauth_access.token_last_eight, access.token_last_eight
        assert_equal @oauth_access.created_at.to_i, access.created_at.to_i
        assert_equal @oauth_access.accessed_at&.to_i, access.accessed_at.to_i
        assert_equal @oauth_access.accessed_at?, access.accessed_at?
        assert_equal @oauth_access.scopes, access.scopes


        assert_equal @oauth_access.id.class, access.id.class
        assert_equal @oauth_access.user_id.class, access.user_id.class
        assert_equal @oauth_access.user.id.class, access.user&.id.class
        assert_equal @oauth_access.application.id.class, access.application&.id.class
        assert_equal @oauth_access.oauth_application&.id.class, access.oauth_application&.id.class
        assert_equal @oauth_access.hashed_token.class, access.hashed_token.class
        assert_equal @oauth_access.code.class, access.code.class
        assert_equal @oauth_access.description.class, access.description.class
        assert_equal @oauth_access.token_last_eight.class, access.token_last_eight.class
        assert_equal @oauth_access.created_at.to_i.class, access.created_at.to_i.class
        assert_equal @oauth_access.accessed_at&.to_i.class, access.accessed_at.to_i.class
        assert_equal @oauth_access.accessed_at?.class, access.accessed_at?.class
        assert_equal @oauth_access.scopes.class, access.scopes.class

        # Test that credential_authorizations returns the correct association
        assert_equal @oauth_access.credential_authorizations.to_a, access.credential_authorizations.to_a
      end

      test "personal token specific behavior" do
        pat = OauthAccessTokens.domain.by_id(@personal_token.id)
        refute_nil pat, "Personal token should not be nil"
        pat = T.must(pat)

        # Verify we get correct behavior for personal token specific methods
        assert_equal @personal_token.id, pat.id
        assert_equal @personal_token.description, pat.description
      end

      test "domain returns objects that behave like OauthAccess models" do
        # Get models via different domain methods to ensure consistency
        by_id = OauthAccessTokens.domain.by_id(@oauth_access.id)
        refute_nil by_id, "by_id result should not be nil"
        by_id = T.must(by_id)

        by_hash = OauthAccessTokens.domain.by_hash(@oauth_access.hashed_token)
        refute_nil by_hash, "by_hash result should not be nil"
        by_hash = T.must(by_hash)

        # Direct comparison with original model
        assert_equal @oauth_access.id, by_id.id
        assert_equal @oauth_access.id, by_hash.id

        # Test that the returned objects are compatible with Rails associations
        assert_equal @user.id, by_id.user&.id
        assert_equal @oauth_application.id, by_id.oauth_application&.id
      end

      test "handles application polymorphism correctly" do
        # Test with OauthApplication
        oauth_app_access = OauthAccessTokens.domain.by_id(@oauth_access.id)
        refute_nil oauth_app_access, "OAuth app access should not be nil"
        oauth_app_access = T.must(oauth_app_access)

        assert_equal "OauthApplication", oauth_app_access.application&.class&.name
        assert_equal @oauth_application.id, oauth_app_access.oauth_application&.id
        assert_nil oauth_app_access.integration

        # Test with Integration
        integration_access = create(:oauth_access, user: @user, application: @integration)
        integration_access_model = OauthAccessTokens.domain.by_id(integration_access.id)
        refute_nil integration_access_model, "Integration access should not be nil"
        integration_access_model = T.must(integration_access_model)

        assert_equal "Integration", integration_access_model.application&.class&.name
        assert_equal @integration.id, integration_access_model.integration&.id
        assert_nil integration_access_model.oauth_application
      end

      test "handles installation polymorphism correctly" do
        # Create an access with an installation
        access_with_installation = create(:oauth_access, user: @user, application: @integration, installation: @installation)

        # Get it through the domain
        access = OauthAccessTokens.domain.by_id(access_with_installation.id)
        refute_nil access, "Access with installation should not be nil"
        access = T.must(access)

        # Check the installation relationship
        assert_equal @installation.id, access.installation&.id
        assert_equal "ScopedIntegrationInstallation", access.installation&.class&.name

        # Verify we can navigate the relationships
        assert_equal @integration.id, access.installation&.integration&.id
        assert_equal @user.id, access.user&.id
      end
    end
  end
end
