# typed: true
# frozen_string_literal: true

require "test_helper"

class ApiActorTest < GitHub::TestCase
  fixtures do
    @admin = create :paid_user
    @org = create :business_plus_org, admin: @admin
    @provider = create :organization_saml_provider, organization: @org
    @member = create(:user)
    @another_member = create(:user)
    @random_user = create(:user)
    @org.add_member(@member)
    @org.add_member(@another_member)
    @org.saml_provider.enforce!

    # Create an enterprise linked organization to test internal repository visibility
    @enterprise_org = create(:enterprise_linked_organization, name: "enterpriseorg")
    @enterprise_member = create(:user)
    @enterprise_org.add_member(@enterprise_member)
    @enterprise_org.add_member(@member)
    @enterprise_org.add_member(@another_member)
    @enterprise_saml_provider = create :organization_saml_provider, organization: @enterprise_org
    @enterprise_org.saml_provider.enforce!

    # Create a second org for `enterprise_org`'s enterprise to test visibility of forked internal repos
    # Note, this enterprise does not set up saml
    @enterprise_org_2 = create :organization
    @enterprise_org_2_user = create :user
    @enterprise_org_2.add_member @enterprise_org_2_user
    create :business_organization_membership, business: @enterprise_org.business, organization: @enterprise_org_2

    @non_saml_org = create(:organization)
    @non_saml_org.add_member(@member)
    @non_saml_org.add_member(@another_member)

    @external_identity = create :external_identity, user: @member, provider: @provider
    @external_identity_enterprise = create :external_identity, user: @enterprise_member, provider: @enterprise_saml_provider

    session = create :user_session, user: @enterprise_member
    create :external_identity_session, user_session: session, external_identity: @external_identity_enterprise

    session = create :user_session, user: @member
    create :external_identity_session, user_session: session, external_identity: @external_identity

    session = create :user_session, user: @another_member
    create :external_identity_session, expires_at: 1.day.ago

    create :user_session, user: @random_user

    # Create some repos on the SAML org
    @org_priv_repo = create :private_repository, owner: @org, name: "orgpriv"
    @org_pub_repo = create :repository, owner: @org, name: "orgpub"

    # Create internal and private repos on the enterprise linked org
    @enterprise_internal_repo = create :internal_repository, owner: @enterprise_org, name: "entinternal"
    @enterprise_priv_repo = create :private_repository, owner: @enterprise_org, name: "entpriv"

    # Allow forking on @enterprise_internal_repo in @enterprise_org
    @enterprise_org.business.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @enterprise_org.allow_private_repository_forking(actor: @admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    # Create a forked internal repo
    @enterprise_internal_fork_repo = create :fork_repository, organization: @enterprise_org, forker: @enterprise_member, fork_repo: @enterprise_internal_repo

    # Create some repos on the non-SAML org
    @non_saml_org_priv_repo = create :private_repository, owner: @non_saml_org, name: "non_saml_orgpriv"
    @non_saml_org_pub_repo = create :repository, owner: @non_saml_org, name: "non_saml_orgpub"

    # Create some user owned repos
    @pub_repo = create(:public_repository, owner: @member, name: "pub")
    @deleted_repo = create :private_repository, :soft_deleted, owner: @org
    @priv_repo = create :private_repository, owner: @member, name: "priv"
    @priv_repo.archived_at = Time.now
    @priv_repo.save
    @another_priv_repo = create :private_repository, owner: @another_member, name: "anotherpriv"
    @random_user_priv_repo = create :private_repository, owner: @random_user
  end

  context "user with valid CAP on org" do
    test "org private repos visible with oauth token" do
      result = make_oauth_token_with_sso_blessing(@member, @org)

      actor = ::BlackbirdSearch::ApiActor::new(actor: result.user, remote_ip: "10.10.10.10")
      assert_same_elements [
        @org_priv_repo.id,
        @non_saml_org_priv_repo.id,
        @priv_repo.id,
        ], actor.accessible_repository_ids
      assert_same_elements [@org.id, @enterprise_org.id, @enterprise_org_2.id, @non_saml_org.id], actor.authorized_organization_ids.sort
      assert_equal [@enterprise_org.id], actor.protected_organization_ids
    end

    test "org internal repos visible with oauth token" do
      result = make_oauth_token_with_sso_blessing(@member, @enterprise_org)

      actor = ::BlackbirdSearch::ApiActor::new(actor: result.user, remote_ip: "10.10.10.10")
      assert_same_elements [
        @non_saml_org_priv_repo.id,
        @priv_repo.id,
        @enterprise_priv_repo.id,
        @enterprise_internal_repo.id,
        @enterprise_internal_fork_repo.id
      ], actor.accessible_repository_ids.sort
      assert_same_elements [@enterprise_org.id, @enterprise_org_2.id, @non_saml_org.id], actor.authorized_organization_ids.sort
      assert_equal [@org.id], actor.protected_organization_ids.sort
    end

    test "internal repo and its fork visible across enterprise-linked orgs" do
      result = make_oauth_token_with_sso_blessing(@enterprise_org_2_user, @enterprise_org_2)
      actor = ::BlackbirdSearch::ApiActor::new(actor: result.user, remote_ip: "10.10.10.10")

      assert_same_elements [
        @enterprise_internal_repo.id,
        @enterprise_internal_fork_repo.id
      ], actor.accessible_repository_ids.sort
      assert_same_elements [@enterprise_org.id, @enterprise_org_2.id], actor.authorized_organization_ids.sort
      assert_equal [], actor.protected_organization_ids.sort
    end
  end

  context "when accessing repos in an enterprise linked org" do
    context "when user has valid CAP" do
      test "org internal repos visible with oauth token via ApiActor" do
        result = make_oauth_token_with_sso_blessing(@enterprise_member, @enterprise_org)

        actor = ::BlackbirdSearch::ApiActor::new(actor: result.user, remote_ip: "10.10.10.10")
        assert_same_elements [
          @enterprise_priv_repo.id,
          @enterprise_internal_repo.id,
          @enterprise_internal_fork_repo.id,
        ], actor.accessible_repository_ids
        assert_same_elements [@enterprise_org.id, @enterprise_org_2.id], actor.authorized_organization_ids.sort
        assert_equal [], actor.protected_organization_ids
      end
    end

    context "when user hasn't authorized a token for an org with SSO" do
      test "internal repos are inaccessible" do
        result = make_oath_token_no_sso(@another_member, @enterprise_org)
        actor = ::BlackbirdSearch::ApiActor::new(actor: result.user, remote_ip: "10.10.10.10")

        refute_includes actor.accessible_repository_ids, @enterprise_internal_repo.id
      end
    end
  end

  def make_oauth_token_with_sso_blessing(user, org)
    pat = make_personal_access_token(user, "repo")
    token = pat.set_random_token_pair
    pat.save
    Organization::CredentialAuthorization.grant(
      organization: org,
      credential: pat,
      actor: user,
    )

    assert token.present?, "token is required"

    result_from_token(token)
  end

  def make_oath_token_no_sso(user, org)
    pat = make_personal_access_token(user, "repo")
    token = pat.set_random_token_pair
    pat.save

    assert token.present?, "token is required"

    result_from_token(token)
  end

  def result_from_token(token)
    result = GitHub::Authentication::Attempt.new(
      allow_integrations: true,
      allow_user_via_granular_actor: true,
      from: :blackbird,
      token: token,
      ip: "10.10.10.10",
      user_agent: "Mozilla/1",
      request_id: "request_id",
      password_auth_blocked: true,
      url: Rack::RequestLogger.url_for_logging("https://github.com"),
    ).result
    if result.failure?
      p "Authentication attempt failure reason: ", result.failure_reason
    end
    assert result.success?, "Authentication attempt failed."

    result
  end
end
