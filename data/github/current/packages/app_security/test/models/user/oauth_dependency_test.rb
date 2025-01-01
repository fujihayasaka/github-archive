# typed: true
# frozen_string_literal: true

require "test_helper"

class UserOAuthDependencyTest < GitHub::TestCase
  fixtures do
    @user   = create(:user)
    @staff  = create(:staff_admin_user)
    @app    = create(:oauth_application,
      user: @staff,
      name: "Code Scanner Pro",
    )
    @user_access = create(:oauth_access, application: @app, user: @user)
    @user_authorization = @user_access.authorization

    make_trusted_oauth_apps_owner
    @github_app = create(:oauth_application,
      user: GitHub.trusted_oauth_apps_owner,
      name: "GitHub Code Scanner Pro",
    )
    @user_github_app_access = create(:oauth_access, application: @github_app, user: @user)
    @user_github_app_authorization = @user_github_app_access.authorization
    @user_pat = create(:personal_token_oauth_access, user: @user)
    @user_pat_authorization = @user_pat.authorization
  end

  test "revokes third party accesses synchronously" do
    assert_equal 3, @user.oauth_accesses.count
    assert_same_elements [@user_authorization, @user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
    @user.revoke_oauth_tokens(:third_party)
    @user.reload
    assert_equal 2, @user.oauth_accesses.count
    assert_same_elements [@user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
    assert_equal 2, @user.oauth_accesses.count
    assert_same_elements [@user_github_app_access, @user_pat], @user.oauth_accesses
  end

  test "revokes third party accesses asynchronously" do
    perform_enqueued_jobs(only: [RemoveOauthUserTokensJob]) do
      assert_equal 3, @user.oauth_accesses.count
      assert_same_elements [@user_authorization, @user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
      @user.async_revoke_oauth_tokens(:third_party)
      @user.reload
      assert_equal 2, @user.oauth_accesses.count
      assert_same_elements [@user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
      assert_equal 2, @user.oauth_accesses.count
      assert_same_elements [@user_github_app_access, @user_pat], @user.oauth_accesses
    end
  end

  test "revokes personal access tokens synchronously" do
    assert_equal 3, @user.oauth_accesses.count
    assert_same_elements [@user_authorization, @user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
    @user.revoke_oauth_tokens(:personal_tokens)
    @user.reload
    assert_equal 2, @user.oauth_accesses.count
    assert_same_elements [@user_github_app_authorization, @user_authorization], @user.oauth_authorizations
    assert_equal 2, @user.oauth_accesses.count
    assert_same_elements [@user_github_app_access, @user_access], @user.oauth_accesses
  end

  test "revokes personal access tokens asynchronously" do
    perform_enqueued_jobs(only: [RemoveOauthUserTokensJob]) do
      assert_equal 3, @user.oauth_accesses.count
      assert_same_elements [@user_authorization, @user_github_app_authorization, @user_pat_authorization], @user.oauth_authorizations
      @user.async_revoke_oauth_tokens(:personal_tokens)
      @user.reload
      assert_equal 2, @user.oauth_accesses.count
      assert_same_elements [@user_github_app_authorization, @user_authorization], @user.oauth_authorizations
      assert_equal 2, @user.oauth_accesses.count
      assert_same_elements [@user_github_app_access, @user_access], @user.oauth_accesses
    end
  end

  test "asynchronous deletes queues a job" do
    assert_enqueued_with job: RemoveOauthUserTokensJob, args: [@user.id, :third_party] do
      @user.async_revoke_oauth_tokens(:third_party)
    end
  end

  test "synchronous deletes don't queue a remove-oauth-user-tokens job" do
    assert_enqueued_with job: ClearAbilitiesJob, args: [@user_authorization.ability_id, @user_authorization.ability_type] do
      assert_enqueued_jobs 0, only: RemoveOauthUserTokensJob do
        @user.revoke_oauth_tokens(:third_party)
      end
    end
  end

  test "raises an exception if you try to delete an unknown token type" do
    perform_enqueued_jobs(only: [RemoveOauthUserTokensJob]) do
      assert_raises ArgumentError do
        @user.revoke_oauth_tokens(:invalid_token_type)
      end

      assert_raises ArgumentError do
        @user.async_revoke_oauth_tokens(:invalid_token_type)
      end
    end
  end

  test "revoke_oauth_tokens_for_oauth_apps only revokes for specified apps" do
    app2 = create(:oauth_application, user: @staff, name: "New App")
    app2_user_access = create(:oauth_access, application: app2, user: @user)
    assert_same_elements(
      [
        @user_authorization,
        @user_github_app_authorization,
        @user_pat_authorization,
        app2_user_access.authorization,
      ],
      @user.oauth_authorizations
    )
    @user.revoke_oauth_tokens_for_oauth_apps(app2)
    @user.reload
    assert_same_elements [@user_github_app_authorization, @user_authorization, @user_pat_authorization], @user.oauth_authorizations
    assert_same_elements [@user_github_app_access, @user_access, @user_pat], @user.oauth_accesses
  end

  test "revoke_oauth_tokens_for_oauth_apps does not revoke integration oauth accesses" do
    integration = create(:integration, id: @app.id)
    grant = integration.grant(@user)
    User.with_oauth_token(grant.reset_token)

    assert_equal integration.id, @app.id
    assert_same_elements(
      [
        @user_authorization,
        @user_github_app_authorization,
        @user_pat_authorization,
        grant.authorization,
      ],
      @user.oauth_authorizations
    )
    @user.revoke_oauth_tokens_for_oauth_apps(@app.id)
    @user.reload
    assert_same_elements [@user_github_app_authorization, @user_pat_authorization, grant.authorization], @user.oauth_authorizations
    assert_same_elements [@user_github_app_access, @user_pat, grant], @user.oauth_accesses
  end

  test "revoke_specific_oauth_tokens only revokes specified accesses" do
    user_access2 = create(:oauth_access, application: @app, user: @user)
    oauth_authorizations = @user.oauth_authorizations
    assert_same_elements(
      [
        @user_github_app_access,
        @user_pat,
        @user_access,
        user_access2,
      ],
      @user.oauth_accesses,
    )
    @user.revoke_specific_oauth_tokens(@user_access.id)
    @user.reload
    assert_same_elements oauth_authorizations, @user.oauth_authorizations
    assert_same_elements [@user_github_app_access, @user_pat, user_access2], @user.oauth_accesses
  end

  test "personal_tokens_for_account_recovery filters on created_by" do
    created_by = Time.current
    include_token = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: created_by, expires_at_timestamp: (Time.current + 1.minute).to_i)
    exclude_token = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: created_by + 1.minute, expires_at_timestamp: (Time.current + 1.minute).to_i)

    pats = @user.personal_tokens_for_account_recovery(created_by)

    assert_same_elements [include_token], pats
  end

  test "personal_tokens_for_account_recovery filters on expiration" do
    include_token1 = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: Time.current, expires_at_timestamp: (Time.current + 1.minute).to_i)
    include_token2 = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: Time.current, expires_at_timestamp: nil)
    exclude_token = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: Time.current, expires_at_timestamp: (Time.current - 1.minute).to_i)

    pats = @user.personal_tokens_for_account_recovery(Time.current)

    assert_same_elements [include_token1, include_token2], pats
  end

  test "personal_tokens_for_account_recovery filters on scope" do
    include_token = create(:personal_token_oauth_access, user: @user, scopes: ["repo"], created_at: Time.current, expires_at_timestamp: (Time.current + 1.minute).to_i)
    exclude_token1 = create(:personal_token_oauth_access, user: @user, scopes: ["user"], created_at: Time.current, expires_at_timestamp: (Time.current + 1.minute).to_i)
    exclude_token2 = create(:personal_token_oauth_access, user: @user, scopes: nil, created_at: Time.current, expires_at_timestamp: (Time.current + 1.minute).to_i)

    pats = @user.personal_tokens_for_account_recovery(Time.current)

    assert_same_elements [include_token], pats
  end

  test "personal_tokens_for_account_recovery limits, ordering by created_at" do
    Timecop.freeze do
      now = Time.current

      testuser = create(:user)
      include_token1 = create(:personal_token_oauth_access, user: testuser, scopes: ["repo"], created_at: now - 1.minute, expires_at_timestamp: (now + 1.minute).to_i)
      include_token2 = create(:personal_token_oauth_access, user: testuser, scopes: ["repo"], created_at: now - 1.minute, expires_at_timestamp: (now + 1.minute).to_i)
      include_token3 = create(:personal_token_oauth_access, user: testuser, scopes: ["repo"], created_at: now - 1.minute, expires_at_timestamp: (now + 1.minute).to_i)
      exclude_token = create(:personal_token_oauth_access, user: testuser, scopes: ["repo"], created_at: now - 1.hour, expires_at_timestamp: (now + 1.minute).to_i)

      pats = testuser.personal_tokens_for_account_recovery(now + 1.minute, limit: 3)

      assert_same_elements [include_token1, include_token2, include_token3], pats
    end
  end

  context "#site_admin_scope_allowed?" do
    if GitHub.enterprise?
      test "returns true for site admins" do
        assert_predicate @staff, :site_admin_scope_allowed?
      end

      test "returns false for non site admins" do
        refute_predicate @user, :site_admin_scope_allowed?
      end
    else
      test "returns false for non site admins" do
        refute_predicate @user, :site_admin_scope_allowed?
      end

      test "returns false for site admins on regular hosts" do
        GitHub.stubs(:admin_host?).returns(false)
        refute_predicate @staff, :site_admin_scope_allowed?
      end

      test "returns true for site admins on admin hosts" do
        GitHub.stubs(:admin_host?).returns(true)
        assert_predicate @staff, :site_admin_scope_allowed?
      end

      test "returns true for site admins in development" do
        Rails.env.stubs(:development?).returns(true)
        assert_predicate @staff, :site_admin_scope_allowed?
      end

      test "returns true for site admins on proxima stafftool tenants" do
        GitHub.stubs(:multi_tenant_enterprise?).returns(true)
        GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
        assert_predicate @staff, :site_admin_scope_allowed?
      end
    end
  end
end
