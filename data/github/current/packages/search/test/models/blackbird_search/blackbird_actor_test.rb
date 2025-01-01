# typed: true
# frozen_string_literal: true

require "test_helper"

class BlackbirdActorTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include ApiReposTestFixtures
  include AuthndClientTestHelpers

  fixtures do
    @user = create(:user, color_mode: ColorMode::LIGHT)
    @admin = create(:paid_user)
    @org = create(:organization, admin: @admin)
    @member = create(:user)
    @another_member = create(:user)
    @org.add_member(@member)
    @org.add_member(@another_member)

    # A session is required for users to mint access tokens.
    create(:user_session, user: @user)
    create(:user_session, user: @member)

    # Create some repos
    @org_priv_repo = create(:private_repository, owner: @org, name: "orgpriv")
    @org_priv_repo_2 = create(:private_repository, owner: @org, name: "orgpriv2")
    @org_pub_repo = create(:repository, owner: @org, name: "orgpub")

    @pub_repo = create(:public_repository, owner: @member, name: "pub")
    @priv_repo = create(:private_repository, owner: @member, name: "priv", force_user_owned: true)
    @another_priv_repo = create(:private_repository, owner: @another_member, name: "anotherpriv", force_user_owned: true)

    @ip_addr = "127.0.0.1"
    @user_agent = "test"
    @request_id = "test"
    @request_url = "test"

    # Dedicated setup for saml, sso and business orgs
    @saml_user = create(:user)
    @saml_org = create(:business_plus_org, admin: @saml_user)
    @saml_org.add_member(@saml_user)
    @no_sso_user = create(:user)
    @saml_org.add_member(@no_sso_user)
    @expired_sso_user = create(:user)
    @saml_org.add_member(@expired_sso_user)
    @saml_org_repo = create(:private_repository, owner: @saml_org)

    saml_provider = create(:organization_saml_provider, organization: @saml_org)
    saml_provider.enforce! unless TestEnv.test_with_all_emus?

    # Valid SSO session
    session = create(:user_session, user: @saml_user)
    external_identity = create(:external_identity, user: @saml_user, provider: saml_provider)
    create(:external_identity_session, user_session: session, external_identity: external_identity)

    # Does not have an SSO session
    create(:user_session, user: @no_sso_user)

    # SSO session is expired
    session = create(:user_session, user: @expired_sso_user)
    external_identity = create(:external_identity, user: @expired_sso_user, provider: saml_provider)
    create(:external_identity_session, user_session: session, external_identity: external_identity, expires_at: 1.day.ago)
  end

  def create_exchange_token(user:, expires: 1.minute.from_now)
    GitHub::Authentication::SignedAuthToken.generate(
      session: user.sessions.first,
      scope: "Blackbird::ExchangeToken",
      expires: expires,
    )
  end

  def create_access_token(user:, expires: 5.minutes.from_now)
    GitHub::Authentication::SignedAuthToken.generate(
      session: user.sessions.first,
      scope: Search::Blackbird::TOKEN_SCOPE,
      expires: expires,
    )
  end

  # Assert that the accessible_repository_ids returned by authorizing the actor match the expected resources.
  # Note: emu test mode factories create extra internal repositories that all org members have access to.
  def assert_accessible_repositories(accessible_repository_ids, expected_ids, business)
    internal_repo_ids = (business&.organizations || []).map { |org| org.internal_repositories.pluck(:id) }.flatten
    expected_ids.concat(internal_repo_ids)
    assert_same_elements(expected_ids.uniq, accessible_repository_ids)
  end

  # Assert that the authorized_organization_ids returned by by authorizing the actor match the expected resources.
  # Note: emu test mode factories create extra organizations that all org members have access to.
  def assert_accessible_organizations(accessible_organization_ids, expected_ids, business)
    expected_ids.concat(business&.organization_ids || [])
    assert_same_elements(expected_ids.uniq, accessible_organization_ids)
  end

  context "user session authorization (i.e. web sessions)" do
    test "basic session" do
      token = create_access_token(user: @member)
      authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )
      assert authed_token.valid?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: authed_token.user,
        session: authed_token.session,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)
      assert_accessible_repositories(
        accessible_resources.accessible_private_repo_ids,
        [@org_priv_repo.id, @org_priv_repo_2.id, @priv_repo.id],
        @org.business
      )
    end

    test "session with sso" do
      token = create_access_token(user: @saml_user)
      authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )
      assert authed_token.valid?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: authed_token.user,
        session: authed_token.session,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)
      assert_accessible_repositories(
        accessible_resources.accessible_private_repo_ids,
        [@saml_org_repo.id],
        @saml_org.business
      )
      assert_accessible_organizations(
        accessible_resources.authorized_organization_ids,
        [@saml_org.id],
        @saml_org.business
      )
      assert_empty accessible_resources.protected_organization_ids
    end

    test "session without sso", skip_with_all_emus: true do
      token = create_access_token(user: @no_sso_user)
      authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )
      assert authed_token.valid?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: authed_token.user,
        session: authed_token.session,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)
      assert_empty accessible_resources.accessible_private_repo_ids
      assert_empty accessible_resources.authorized_organization_ids
      assert_equal [@saml_org.id], accessible_resources.protected_organization_ids
    end

    test "session with expired sso", skip_with_all_emus: true do
      token = create_access_token(user: @expired_sso_user)
      authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )
      assert authed_token.valid?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: authed_token.user,
        session: authed_token.session,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)
      assert_empty accessible_resources.accessible_private_repo_ids
      assert_empty accessible_resources.authorized_organization_ids
      assert_equal [@saml_org.id], accessible_resources.protected_organization_ids
    end

    test "session with business org" do
      internal_repo = create :internal_repository
      biz = internal_repo.owner.business
      biz_owner = biz.owners.first
      other_biz_org = create :enterprise_linked_organization, business: biz
      other_biz_user = create :user
      other_biz_org.add_member(other_biz_user, adder: other_biz_org.admins.first)

      [biz_owner, other_biz_user].each do |user|
        create :user_session, user: user
        token = create_access_token(user: user)
        authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
          token: token,
          scope: Search::Blackbird::TOKEN_SCOPE,
        )
        assert authed_token.valid?

        blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
          actor: authed_token.user,
          session: authed_token.session,
          request_user_ip: @ip_addr,
          token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
        )

        accessible_resources = T.must(blackbird_actor.accessible_resources)
        assert_accessible_repositories(
          accessible_resources.accessible_private_repo_ids,
          [internal_repo.id],
          biz
        )
        assert_same_elements biz.organizations.pluck(:id), accessible_resources.authorized_organization_ids
      end
    end

    test "session with outside collaborators", skip_with_all_emus: true do
      outside_collaborator = create(:user, login: "collab-user")
      create(:user_session, user: outside_collaborator)
      create(:public_repository, owner: outside_collaborator, name: "collab-repo")

      # outside collaborator on one org-owned and one user-owned repo.
      @org_priv_repo.add_member(outside_collaborator, action: :read)
      assert @pub_repo.add_member(outside_collaborator)

      token = create_access_token(user: outside_collaborator)
      authed_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )
      assert authed_token.valid?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: authed_token.user,
        session: authed_token.session,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB,
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)
      assert_equal [outside_collaborator.id, @org.id, @member.id], accessible_resources.accessible_owner_ids
    end
  end

  context "authorization for legacy PATs (OauthAccess)" do
    test "member legacy PAT" do
      # To validate that a user's legacy PAT is only authorized for a single org, we create a second org and add the user.
      org2 = create(:business_plus_org)
      org2.add_member(@member)

      # The second org has private repos that the user can access.
      org2_priv_repo = create(:private_repository, owner: org2)
      saml_provider = create(:organization_saml_provider, organization: org2)
      saml_provider.enforce! unless TestEnv.test_with_all_emus?

      # But the user's PAT is only authorized for accessing repos in the first org.
      pat = make_personal_access_token(@member, "repo")
      token = pat.set_random_token_pair
      pat.save
      Organization::CredentialAuthorization.grant(
        organization: @org,
        credential: pat,
        actor: @member,
      )

      auth_result = GitHub::Authentication::Attempt.new(
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        from: :blackbird,
        token: token,
        ip: @request_user_ip,
        user_agent: @user_agent,
        request_id: @request_id,
        password_auth_blocked: true,
      ).result
      assert auth_result.success?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: auth_result.user,
        session: auth_result.user.sessions.last,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
        request_user_ip: @ip_addr
      )

      accessible_resources = T.must(blackbird_actor.accessible_resources)

      actual_private_repo_ids = accessible_resources.accessible_private_repo_ids

      # We verify that the PAT's access does not leak any private repos in the second org.
      refute_includes actual_private_repo_ids, org2_priv_repo.id

      # We verify that the first org's private repos are included in the set of accessible repos,
      # along with private repos owned directly by the user.
      expected = [@org_priv_repo.id, @org_priv_repo_2.id, @priv_repo.id]
      expected.each do |id|
        assert_includes actual_private_repo_ids, id
      end

      # NB: The emu test mode factories create extra internal repositories that @member has access to.
      # We assert that those repos are "internal" and owned by the first @org. This is slightly different than
      # assert_accessible_repositories as the token only has access to a SINGLE organization.
      (T.must(actual_private_repo_ids) - expected).each do |id|
        repo = Repositories::Public.get_active_or_deleted!(id)
        assert repo.internal?
        assert_equal repo.owner, @org
      end
    end

    test "legacy PAT without repo scope" do
      org2 = create(:business_plus_org)
      org2.add_member(@member)
      create(:private_repository, owner: org2)
      saml_provider = create(:organization_saml_provider, organization: org2)
      saml_provider.enforce! unless TestEnv.test_with_all_emus?

      pat = make_personal_access_token(@member, [])
      token = pat.set_random_token_pair
      pat.save

      Organization::CredentialAuthorization.grant(
        organization: @org,
        credential: pat,
        actor: @member,
      )

      auth_result = GitHub::Authentication::Attempt.new(
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        from: :blackbird,
        token: token,
        ip: @request_user_ip,
        user_agent: @user_agent,
        request_id: @request_id,
        password_auth_blocked: true,
      ).result
      assert auth_result.success?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: auth_result.user,
        session: auth_result.user.sessions.last,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
      )

      assert_equal(
        {
          accessible_private_repo_ids: [],
          accessible_owner_ids: [@member.id, @org.id],
          authorized_organization_ids: [@org.id],
          protected_organization_ids: [org2.id],
        },
        T.must(blackbird_actor.accessible_resources).to_h
      )
    end
  end

  context "authorization for fine-grained PATs (UserProgrammaticAccess)" do
    test "member programmatic access (fine-grained PATs)" do
      GitHub.flipper[:saml_org_ids_via_fg_pats].enable

      with_authnd_stub do
        access = make_user_programmatic_access_with_grant({
          requester: @member,
          target: @member,
          permissions: { "metadata" => :read, "contents" => :read },
          repositories: [@priv_repo],
          repository_selection: :subset,
        })

        stub_authnd_programmatic_access_issue_token
        result = ProgrammaticAccessToken.generate(access)

        if result.failed?
          raise ArgumentError, "failed to generate token"
        end

        stub_authnd_programmatic_access_token(access, result.value)

        auth_result = GitHub::Authentication::Attempt.new(
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          from: :blackbird,
          token: result.value,
          ip: @request_user_ip,
          user_agent: @user_agent,
          request_id: @request_id,
          password_auth_blocked: true,
        ).result
        assert auth_result.success?

        blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
          actor: auth_result.user,
          session: auth_result.user.sessions.last,
          request_user_ip: @ip_addr,
          token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
        )

        assert_equal(
          {
            accessible_private_repo_ids: [@priv_repo.id],
            accessible_owner_ids: [@member.id, @org.id],
            authorized_organization_ids: [@org.id],
            protected_organization_ids: [],
          },
          T.must(blackbird_actor.accessible_resources).to_h
        )
      end
    end

    test "granular token through API grants access to authorized org repositories" do
      GitHub.flipper[:saml_org_ids_via_fg_pats].enable

      with_authnd_stub do
        access = make_user_programmatic_access_with_grant({
          requester: @member,
          target: @org,
          permissions: { "metadata" => :read, "contents" => :read },
          repositories: [@org_priv_repo],
          repository_selection: :subset,
        })

        stub_authnd_programmatic_access_issue_token
        result = ProgrammaticAccessToken.generate(access)

        stub_authnd_programmatic_access_token(access, result.value)

        auth_result = GitHub::Authentication::Attempt.new(
          allow_integrations: true,
          allow_user_via_granular_actor: true,
          from: :blackbird,
          token: result.value,
          ip: @request_user_ip,
          user_agent: @user_agent,
          request_id: @request_id,
          password_auth_blocked: true,
        ).result
        assert auth_result.success?

        blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
          actor: auth_result.user,
          session: auth_result.user.sessions.last,
          request_user_ip: @ip_addr,
          token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
        )

        assert_equal(
          {
            accessible_private_repo_ids: [@org_priv_repo.id],
            accessible_owner_ids: [@member.id, @org.id],
            authorized_organization_ids: [@org.id],
            protected_organization_ids: [],
          },
          T.must(blackbird_actor.accessible_resources).to_h
        )
      end
    end
  end

  context "authorization for integration installations" do
    test "for integration installations" do
      installation = make_integration_installation(
        target: @org,
        repositories: [@org_priv_repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )
      auth_token, token = AuthenticationToken.create_for(installation)

      auth_result = GitHub::Authentication::Attempt.new(
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        from: :blackbird,
        token: token,
        ip: @request_user_ip,
        user_agent: @user_agent,
        request_id: @request_id,
        password_auth_blocked: true,
      ).result
      assert auth_result.success?

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: auth_result.user,
        session: auth_result.user.sessions.last,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
      )

      assert_equal(
        {
          accessible_private_repo_ids: [@org_priv_repo.id],
          accessible_owner_ids: [installation.bot.id, @org.id],
          authorized_organization_ids: [@org.id],
          protected_organization_ids: [],
        },
        T.must(blackbird_actor.accessible_resources).to_h
      )
    end

    test "supports authorizing enterprise installations" do
      key = OpenSSL::PKey::RSA.new(IntegrationKey::KEY_LENGTH).to_pem
      enterprise_installation = create(:enterprise_installation, owner: @org)
      integration, _ = enterprise_installation.create_github_app(key, @admin)
      integration.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case)

      DotcomConnection.any_instance.stubs(:bearer_encoding_key).returns(key)
      DotcomConnection.any_instance.stubs(:installation_issuer).returns(integration.id.to_s)

      token = GitHub::Connect.github_app_bearer_token

      assertion = Api::IntegrationAssertion.new({ "HTTP_AUTHORIZATION" => token })
      assert assertion.valid?
      auth_result = GitHub::Authentication::Result.success(assertion.integration.bot)

      blackbird_actor = BlackbirdSearch::BlackbirdActor.new(
        actor: auth_result.user,
        session: auth_result.user.sessions.last,
        request_user_ip: @ip_addr,
        token_kind: Search::Blackbird::Client::ACCESS_TOKEN_KIND_API,
      )

      assert_equal(
        {
          accessible_private_repo_ids: [],
          accessible_owner_ids: [integration.bot.id],
          authorized_organization_ids: [],
          protected_organization_ids: [],
        },
        T.must(blackbird_actor.accessible_resources).to_h
      )
    end
  end
end unless GitHub.enterprise?
