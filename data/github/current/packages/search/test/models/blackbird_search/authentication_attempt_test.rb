# typed: true
# frozen_string_literal: true

require "test_helper"

class BlackbirdAuthenticationAttemptTest < GitHub::TestCase
  include ApiProgrammaticGrantHelpers
  include ApiReposTestFixtures

  API = Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
  WEB = Search::Blackbird::Client::ACCESS_TOKEN_KIND_WEB

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

  test "invalid API token" do
    auth_result = BlackbirdSearch::AuthenticationAttempt.new(
      token: "",
      token_kind: API,
      request_id: @request_id,
      request_user_ip: @ip_addr,
      user_agent: @user_agent
    ).result

    refute auth_result.success?
    assert_nil auth_result.blackbird_actor
    assert_equal :integration, auth_result.auth_type
    assert_nil auth_result.auth_id

    assert_equal "A JSON web token could not be decoded", auth_result.error
  end

  context "signed authentication tokens (i.e. user sessions)" do
    test "basic session" do
      token = create_access_token(user: @member)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_equal @member.sessions.first.id, auth_result.auth_id
      assert_equal @member, auth_result.actor
    end

    test "session with sso" do
      token = create_access_token(user: @saml_user)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_equal @saml_user.sessions.first.id, auth_result.auth_id
      assert_equal @saml_user, auth_result.actor
    end

    test "session without sso", skip_with_all_emus: true do
      token = create_access_token(user: @no_sso_user)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_equal @no_sso_user.sessions.first.id, auth_result.auth_id
      assert_equal @no_sso_user, auth_result.actor
    end

    test "session with expired sso", skip_with_all_emus: true do
      token = create_access_token(user: @expired_sso_user)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_equal @expired_sso_user.sessions.first.id, auth_result.auth_id
      assert_equal @expired_sso_user, auth_result.actor
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
        auth_result = BlackbirdSearch::AuthenticationAttempt.new(
          token: token,
          token_kind: WEB,
          request_id: @request_id,
          request_user_ip: @ip_addr,
          user_agent: @user_agent
        ).result

        assert auth_result.success?
        refute_nil auth_result.blackbird_actor
        assert_equal :user_session, auth_result.auth_type
        assert_equal user.sessions.first.id, auth_result.auth_id
        assert_equal user, auth_result.actor
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
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_equal outside_collaborator.sessions.first.id, auth_result.auth_id
      assert_equal outside_collaborator, auth_result.actor
    end

    test "invalid token" do
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: "",
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_nil auth_result.auth_id
      assert_nil auth_result.actor

      assert_equal "token format is invalid", auth_result.error
    end

    test "exchange tokens are not supported" do
      token = create_exchange_token(user: @member)
      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: WEB,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal :user_session, auth_result.auth_type
      assert_nil auth_result.auth_id
      assert_nil auth_result.actor

      assert_equal "token is not valid within the scope of this page", auth_result.error
    end
  end

  context "authentication token authorization (i.e. integration installations)" do
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

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :oauth_access, auth_result.auth_type
      assert_equal pat.id, auth_result.auth_id
      assert_equal @member, auth_result.actor
    end

    test "expired legacy PAT" do
      pat = make_personal_access_token(@member, "repo")
      token = pat.set_random_token_pair
      pat.expires_at_timestamp = (Time.current - 1.day).to_i
      pat.save
      Organization::CredentialAuthorization.grant(
        organization: @org,
        credential: pat,
        actor: @member,
      )

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal :oauth_access, auth_result.auth_type
      assert_nil auth_result.auth_id
      assert_nil auth_result.actor
      assert_equal "token", auth_result.error
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

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :oauth_access, auth_result.auth_type
      assert_equal pat.id, auth_result.auth_id
      assert_equal @member, auth_result.actor
    end
  end

  context "user programmatic access authorization (i.e. fine-grained PATs)" do
    test "member programmatic access (fine-grained PATs)" do
      enable_feature_flag(:saml_org_ids_via_fg_pats)

      access = make_user_programmatic_access_with_grant({
        requester: @member,
        target: @member,
        permissions: { "metadata" => :read, "contents" => :read },
        repositories: [@priv_repo],
        repository_selection: :subset,
      })

      result = ProgrammaticAccessTokens.domain.generate(access.user_id, access.id)

      if result.failed?
        raise ArgumentError, "failed to generate token"
      end

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: result.value,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_programmatic_access, auth_result.auth_type
      assert_equal access.id, auth_result.auth_id
      assert_equal @member, auth_result.actor
    end

    test "granular token through API grants access to authorized org repositories" do
      enable_feature_flag(:saml_org_ids_via_fg_pats)

      access = make_user_programmatic_access_with_grant({
        requester: @member,
        target: @org,
        permissions: { "metadata" => :read, "contents" => :read },
        repositories: [@org_priv_repo],
        repository_selection: :subset,
      })

      result = ProgrammaticAccessTokens.domain.generate(access.user_id, access.id)

      if result.failed?
        raise ArgumentError, "failed to generate token"
      end

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: result.value,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :user_programmatic_access, auth_result.auth_type
      assert_equal access.id, auth_result.auth_id
      assert_equal @member, auth_result.actor
    end
  end

  context "authentication tokens (i.e. integration authorizations)" do
    test "for integration installations" do
      installation = make_integration_installation(
        target: @org,
        repositories: [@org_priv_repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )
      auth_token, token = installation.generate_token

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :authentication_token, auth_result.auth_type
      assert_equal auth_token.id, auth_result.auth_id
      authenticatable = auth_token.authenticatable_class.find_by(id: auth_token.authenticatable_id)
      assert_equal authenticatable.bot, auth_result.actor
    end

    test "when integration is missing" do
      installation = make_integration_installation(
        target: @org,
        repositories: [@org_priv_repo],
        permissions: { "metadata" => :read, "contents" => :read },
      )
      auth_token, token = installation.generate_token
      IntegrationInstallation.stubs(:find_by).with(id: installation.id).returns(nil)

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token,
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      # this hits bot.rb while trying to look up the token actor, doesn't resolve the authenticatable,
      #  returns nil actor then returns token failure from access_token_authenticate when user is nil
      refute auth_result.success?
      assert_nil auth_result.blackbird_actor
      assert_equal :authentication_token, auth_result.auth_type
    end
  end

  context "integrations (i.e. enterprise installations)" do
    test "supports authorizing enterprise installations" do
      key = OpenSSL::PKey::RSA.new(IntegrationKey::KEY_LENGTH).to_pem
      enterprise_installation = create(:enterprise_installation, owner: @org)
      integration, _ = enterprise_installation.create_github_app(key, @admin)
      integration.install_on(@org, repositories: [], installer: @admin, entry_point: :test_case)

      DotcomConnection.any_instance.stubs(:bearer_encoding_key).returns(key)
      DotcomConnection.any_instance.stubs(:installation_issuer).returns(integration.id.to_s)

      token = GitHub::Connect.github_app_bearer_token

      auth_result = BlackbirdSearch::AuthenticationAttempt.new(
        token: token.delete_prefix("Bearer "),
        token_kind: API,
        request_id: @request_id,
        request_user_ip: @ip_addr,
        user_agent: @user_agent
      ).result

      assert auth_result.success?
      refute_nil auth_result.blackbird_actor
      assert_equal :integration, auth_result.auth_type
      assert_equal integration.id, auth_result.auth_id
      assert_equal integration.bot, auth_result.actor
    end
  end
end unless GitHub.enterprise?
