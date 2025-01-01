# typed: true
# frozen_string_literal: true

require "test_helper"

class BlackbirdSearchAuthenticationResultTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include ApiReposTestFixtures
  include AuthndClientTestHelpers

  API = Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
  WEB = Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB
  AccessibleResources = Hydro::Schemas::Blackbird::V0::Entities::AccessibleResources

  setup do
    @actor = create(:user)
    @session = create(:user_session, user: @actor)
    @ip_addr = "127.0.0.1"
    @token_kind = ::Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB
  end

  context "success?" do
    test "returns true if blackbird actor is not nil" do
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: BlackbirdSearch::BlackbirdActor.new(actor: @actor, session: @session, request_user_ip: @ip_addr, token_kind: @token_kind),
        auth_type: :user_session,
        auth_id: 1,
        auth_failed_reason: nil,
      )

      assert result.success?
    end

    test "returns false if blackbird actor is nil" do
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: nil,
        auth_type: :user_session,
        auth_id: 1,
        auth_failed_reason: "authenticated actor not found",
      )

      refute result.success?
    end
  end

  context "error" do
    test "returns auth failed reason" do
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: nil,
        auth_type: :user_session,
        auth_id: 1,
        auth_failed_reason: "authenticated actor not found",
      )

      assert_equal "authenticated actor not found", result.error
    end
  end

  context "actor" do
    test "returns actor from blackbird actor" do
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: BlackbirdSearch::BlackbirdActor.new(actor: @actor, session: @session, request_user_ip: @ip_addr, token_kind: @token_kind),
        auth_type: :user_session,
        auth_id: 1,
        auth_failed_reason: nil,
      )

      assert_equal @actor, result.actor
    end
  end

  context "expires_at" do
    test "returns nil if auth type is not user_programmatic_access" do
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: BlackbirdSearch::BlackbirdActor.new(actor: @actor, session: @session, request_user_ip: @ip_addr, token_kind: @token_kind),
        auth_type: :user_session,
        auth_id: 1,
        auth_failed_reason: nil,
      )

      assert_nil result.expires_at
    end

    test "returns expires_at timestamp if auth type is user_programmatic_access and PAT has expiry" do
      upa = UserProgrammaticAccess.new
      upa.expires_at = Time.zone.now
      @actor.programmatic_access = upa
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: BlackbirdSearch::BlackbirdActor.new(actor: @actor, session: @session, request_user_ip: @ip_addr, token_kind: @token_kind),
        auth_type: :user_programmatic_access,
        auth_id: 1,
        auth_failed_reason: nil,
      )

      assert_equal upa.expires_at, result.expires_at
    end

    test "returns nil if auth type is user programmatic access and PAT does not have expiry" do
      upa = UserProgrammaticAccess.new
      @actor.programmatic_access = upa
      result = BlackbirdSearch::AuthenticationResult.new(
        blackbird_actor: BlackbirdSearch::BlackbirdActor.new(actor: @actor, session: @session, request_user_ip: @ip_addr, token_kind: @token_kind),
        auth_type: :user_programmatic_access,
        auth_id: 1,
        auth_failed_reason: nil,
      )

      assert_nil upa.expires_at
      assert_nil result.expires_at
    end
  end

  context "load blackbird actor fails" do
    test "reports error and raises if oauth access is not found" do
      actor = create(:user)
      invalid_oauth_token = ""

      Failbot.expects(:report).with("authenticated actor not found", "gh.auth_type": :oauth_access, "gh.auth_id": 0, catalog_service: "blackbird").once

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: 0,
        auth_type: :oauth_access,
        expires_at: nil,
        request_user_ip: @ip_addr,
        session_id: invalid_oauth_token,
        token_kind: API,
      )

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal auth_result.error, "authenticated actor not found"
    end

    test "reports error and raises if user programmatic access is not found" do
      actor = create(:user)
      invalid_user_programmatic_access = 0

      Failbot.expects(:report).with("authenticated actor not found", "gh.auth_type": :user_programmatic_access, "gh.auth_id": 0, catalog_service: "blackbird").once

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: invalid_user_programmatic_access,
        auth_type: :user_programmatic_access,
        expires_at: nil,
        request_user_ip: @ip_addr,
        session_id: "", # Not used for this test case.
        token_kind: API,
      )

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal auth_result.error, "authenticated actor not found"
    end

    test "reports error and raises if integration is not found" do
      actor = create(:user)
      invalid_integration = 0

      Failbot.expects(:report).with("authenticated actor not found", "gh.auth_type": :integration, "gh.auth_id": 0, catalog_service: "blackbird").once

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: invalid_integration,
        auth_type: :integration,
        expires_at: nil,
        request_user_ip: @ip_addr,
        session_id: "", # Not used for this test case.
        token_kind: API,
      )

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal auth_result.error, "authenticated actor not found"
    end

    test "reports error and raises if authentication token is not found" do
      actor = create(:user)
      invalid_authentication_token = 0

      Failbot.expects(:report).with("authenticated actor not found", "gh.auth_type": :authentication_token, "gh.auth_id": 0, catalog_service: "blackbird").once

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: invalid_authentication_token,
        auth_type: :authentication_token,
        expires_at: nil,
        request_user_ip: @ip_addr,
        session_id: "", # Not used for this test case.
        token_kind: API,
      )

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal auth_result.error, "authenticated actor not found"
    end

    test "reports error and raises if user session is not found" do
      actor = create(:user)
      invalid_session = 0

      Failbot.expects(:report).with("authenticated actor not found", "gh.auth_type": :user_session, "gh.auth_id": 0, catalog_service: "blackbird").once

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: invalid_session,
        auth_type: :user_session,
        expires_at: nil,
        request_user_ip: @ip_addr,
        session_id: "", # Not used for this test case.
        token_kind: WEB,
      )

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal auth_result.error, "authenticated actor not found"
    end
  end

  context "load blackbird actor succeeds" do
    test "user session (i.e. web sessions)" do
      actor = create(:user)
      private_repo = create(:private_repository, owner: actor)
      other_private_repo = create(:private_repository)
      user_session = create(:user_session, user: actor)

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: user_session.id,
        auth_type: :user_session,
        expires_at: nil,
        request_user_ip: "127.0.0.1",
        session_id: user_session.id.to_s, # Not used for this test case.
        token_kind: WEB,
      )
      assert auth_result.success?

      including_emu_orgs = actor.organizations.map { |org| org.business.organization_ids }.flatten.uniq
      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [private_repo.id],
        accessible_owner_ids: [actor.id].concat(including_emu_orgs),
        authorized_organization_ids: including_emu_orgs,
        protected_organization_ids: [],
      )
      assert_equal expected_ar, T.must(auth_result.blackbird_actor).accessible_resources
    end

    test "authentication token (i.e. integratio installations)" do
      actor = create(:user)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo = create(:private_repository, owner: org)
      actor_private_repo = create(:private_repository, owner: actor)

      installation = make_integration_installation(
        target: org,
        repositories: [org_private_repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )
      auth_token, token = AuthenticationToken.create_for(installation)
      session_id = AuthenticationToken.hash_token(token)

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: auth_token.id,
        auth_type: :authentication_token,
        expires_at: nil,
        request_user_ip: "127.0.0.1",
        session_id: "", # Not used for this test case.
        token_kind: API,
      )
      assert auth_result.success?

      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [org_private_repo.id],
        accessible_owner_ids: [installation.bot.id, org.id],
        authorized_organization_ids: [org.id],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, T.must(auth_result.blackbird_actor).accessible_resources
    end

    test "oauth access (i.e. legacy PATs)" do
      actor = create(:user)
      actor_private_repo = create(:private_repository, owner: actor)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo = create(:private_repository, owner: org)

      legacy_pat = make_personal_access_token(actor, "repo")
      Organization::CredentialAuthorization.grant(
        organization: org,
        credential: legacy_pat,
        actor: actor,
      )

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: legacy_pat.id,
        auth_type: :oauth_access,
        expires_at: nil,
        request_user_ip: "127.0.0.1",
        session_id: legacy_pat.hashed_token,
        token_kind: API,
      )
      assert auth_result.success?

      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [actor_private_repo.id, org_private_repo.id],
        accessible_owner_ids: [actor.id, org.id],
        authorized_organization_ids: [org.id],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, T.must(auth_result.blackbird_actor).accessible_resources
    end

    test "user programmatic access (i.e. fine-grained PATs)" do
      actor = create(:user)
      private_repo1 = create(:private_repository, owner: actor, force_user_owned: true)
      private_repo2 = create(:private_repository, owner: actor, force_user_owned: true)
      org = create(:organization)
      org.add_member(actor)

      with_authnd_stub do
        user_programmatic_access = make_user_programmatic_access_with_grant({
          requester: actor,
          target: actor,
          permissions: { "metadata" => :read, "contents" => :read },
          repositories: [private_repo1],
          repository_selection: :subset,
        })

        stub_authnd_programmatic_access_issue_token
        result = ProgrammaticAccessToken.generate(user_programmatic_access)
        assert result.success?

        stub_authnd_programmatic_access_token(user_programmatic_access, result.value)

        auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
          actor: actor,
          auth_id: user_programmatic_access.id,
          auth_type: :user_programmatic_access,
          expires_at: user_programmatic_access.expires_at,
          request_user_ip: "127.0.0.1",
          session_id: "", # Not used for this test case.
          token_kind: API,
        )
        assert auth_result.success?

        expected_ar = AccessibleResources.new(
          accessible_private_repo_ids: [private_repo1.id],
          accessible_owner_ids: [actor.id, org.id],
          authorized_organization_ids: [org.id],
          protected_organization_ids: [],
        )
        assert_equal expected_ar, T.must(auth_result.blackbird_actor).accessible_resources
      end
    end

    test "integration (i.e. enterprise installations)" do
      actor = create(:user)
      org = create(:organization)
      org.add_member(actor)
      org_private_repo1 = create(:private_repository, owner: org)
      org_private_repo2 = create(:private_repository, owner: org)
      actor_private_repo = create(:private_repository, owner: actor)

      enterprise_installation = create(:enterprise_installation, owner: org)
      integration, integration_secret = enterprise_installation.create_github_app
      app_installation = make_integration_installation(integration: integration, target: org, repositories: [org_private_repo1], permissions: { "metadata" => :read, "contents" => :read })
      session_id = AuthenticationToken.hash_token(integration_secret)

      auth_result = BlackbirdSearch::AuthenticationResult.load_auth_result(
        actor: actor,
        auth_id: integration.id,
        auth_type: :integration,
        expires_at: nil,
        request_user_ip: "127.0.0.1",
        session_id: "", # Not used for this test case.
        token_kind: API,
      )
      assert auth_result.success?

      expected_ar = AccessibleResources.new(
        accessible_private_repo_ids: [],
        accessible_owner_ids: [app_installation.bot.id],
        authorized_organization_ids: [],
        protected_organization_ids: [],
      )
      assert_equal expected_ar, T.must(auth_result.blackbird_actor).accessible_resources
    end
  end
end
