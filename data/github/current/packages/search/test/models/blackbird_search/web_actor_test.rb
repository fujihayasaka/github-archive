# typed: true
# frozen_string_literal: true

require "test_helper"

class WebActorTest < GitHub::TestCase
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

  def create_access_token(user:, expires: 5.minutes.from_now)
    token = GitHub::Authentication::SignedAuthToken.generate(
      session: user.sessions.first,
      scope: Search::Blackbird::TOKEN_SCOPE,
      expires: expires,
    )

    GitHub::Authentication::SignedAuthToken::Session.verify(
      token: token,
      scope: Search::Blackbird::TOKEN_SCOPE,
    )
  end

  context "user with valid CAP on org" do
    test "all org private repos are accessible" do
      access_token = create_access_token(user: @member)
      actor = ::BlackbirdSearch::WebActor::new(actor: access_token.user, session: access_token.session)

      assert_same_elements [
        @org_priv_repo.id,
        @non_saml_org_priv_repo.id,
        @priv_repo.id,
        ], actor.accessible_repository_ids.sort

      assert_same_elements [@org.id, @enterprise_org.id, @enterprise_org_2.id, @non_saml_org.id], actor.authorized_organization_ids.sort
      assert_equal [@enterprise_org.id], actor.protected_organization_ids
    end
  end

  context "user without valid CAP on org" do
    test "saml org private repos are not accessible" do
      access_token = create_access_token(user: @another_member)
      actor = ::BlackbirdSearch::WebActor::new(actor: access_token.user, session: access_token.session)
      assert_same_elements [
        @non_saml_org_priv_repo.id,
        @another_priv_repo.id,
        ], actor.accessible_repository_ids.sort

      assert_equal [@enterprise_org.id, @enterprise_org_2.id, @non_saml_org.id], actor.authorized_organization_ids.sort
      assert_equal [@org.id, @enterprise_org.id], actor.protected_organization_ids.sort
    end
  end

  context "when accessing repos in an enterprise linked org" do
    context "when user has valid CAP" do
      test "all enterprise org private/internal repos are accessible via WebActor" do
        access_token = create_access_token(user: @enterprise_member)
        actor = ::BlackbirdSearch::WebActor::new(actor: access_token.user, session: access_token.session)

        assert_same_elements [
          @enterprise_internal_repo.id,
          @enterprise_priv_repo.id,
          @enterprise_internal_fork_repo.id,
        ], actor.accessible_repository_ids.sort

        assert_same_elements [@enterprise_org.id, @enterprise_org_2.id], actor.authorized_organization_ids.sort
        assert_equal [], actor.protected_organization_ids
      end
    end
  end

  context "random user" do
    test "only owned private repos are visible" do
      access_token = create_access_token(user: @random_user)
      actor = ::BlackbirdSearch::WebActor::new(actor: access_token.user, session: access_token.session)
      assert_equal [@random_user_priv_repo.id], actor.accessible_repository_ids
      assert_equal [], actor.authorized_organization_ids
      assert_equal [], actor.protected_organization_ids
    end
  end
end
