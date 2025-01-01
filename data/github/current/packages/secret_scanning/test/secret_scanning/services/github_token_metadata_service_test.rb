# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/permissions_helper"
require "test_helpers/private_token_scanning_test_helper"

class GitHubTokenMetadataServiceTest < GitHub::TestCase

  # Users cannot have apps installed on them in EMU mode.
  skip_with_all_emus

  include PrivateTokenScanningTestHelper
  include AuthndClientTestHelpers
  include ApiProgrammaticGrantHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner
    @user = create(:user)
    @non_member = create(:user)
    @repo_member = create(:user)
    @suspended_repo_member = create(:user)

    @org = create(:organization, admin: @user)
    @org2 = create(:organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @expires_at = Time.parse("2023-02-21 12:00:00 +0000")
    @access_date = Time.parse("2023-02-21 12:00:00 +0000")

    # refresh token
    @integration = create :integration
    @access = create :github_app_access, application: @integration
    @access.redeem
    @refresh_token = @access.refresh_token

    #app installation
    @installation = make_integration_installation(integration: @integration, target: @user)
    @record, @app_token = AuthenticationToken.create_for(@installation)
    @installation_org = make_integration_installation(integration: @integration, target: @org)
    @record_org, @app_token_org = AuthenticationToken.create_for(@installation_org)

    #ssh key
    @private_key_contents, @public_key_contents = generate_ssh_key
    @public_key = create(:public_key, user: @user, key: @public_key_contents)
    @public_key.verify(@user)

    # ssh key belonging to a suspended user
    @private_key_contents_suspended, @public_key_contents_suspended = generate_ssh_key
    @public_key_suspended = create(:public_key, user: @suspended_repo_member, key: @public_key_contents_suspended)
    @public_key.verify(@suspended_repo_member)
    @public_key_suspended.creator_id = @suspended_repo_member.id
    @public_key_suspended.save!

    # deploy key
    @private_key_contents_deploy, @public_key_contents_deploy = generate_ssh_key
    @public_key_deploy = create(:public_key, repository: @repo, key: @public_key_contents_deploy)
    @public_key_deploy.verify(@user)

    #saml
    @business = create :business
    @biz_saml_org = create :enterprise_linked_organization, business: @business
    @biz_saml_provider = create :business_saml_provider, :scim_provisioning_enabled, business: @business
    create :external_identity, provider: @biz_saml_provider, user: @user
    @biz_saml_org.add_member @user
    @saml_repo = create(:repository, owner: @biz_saml_org)

    @patv2_token = T.let(nil, T.nilable(ProgrammaticAccessToken))
    @patv2_access = create :user_programmatic_access, owner: @user, created_at: Time.parse("2023-01-21 12:00:00 +0000")
    @patv2_org_access = create :user_programmatic_access, owner: @org, expires_at: @expires_at
    with_authnd_stub do
      stub_authnd_programmatic_access_issue_token
      @patv2_result = ProgrammaticAccessToken.generate(@patv2_access)
      @patv2_token = @patv2_result.value

      stub_authnd_programmatic_access_issue_token
      @patv2_org_result = ProgrammaticAccessToken.generate(@patv2_org_access)
      @patv2_org_token = @patv2_org_result.value
    end

    if !GitHub.enterprise?
      @emu_user = create :emu, :owner
      @emu_business = @emu_user.enterprise_managed_business
      @emu_org = create(:organization, business: @emu_business, admin: @emu_user)
      @emu_user_repo = create(:private_repository, owner: @emu_user)
      @emu_org_repo = create(:private_repository, owner: @emu_org)
    end
  end

  setup do
    setup_authnd_stub
    @suspended_repo_member.suspend("suspended for testing")
  end

  teardown do
    remove_authnd_stub
  end

  context "#patv1" do
    test "returns all metadata for patv1" do
      pat = make_personal_access_token(@repo_member, scopes = %w(repo))
      pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal pat.created_at, token_metadata&.created_at
      assert_equal @expires_at, token_metadata&.expires_at
      assert_nil token_metadata&.org_access
      assert_equal "PAT Name", token_metadata&.name
      assert_match "/settings/tokens/" + pat.id.to_s, T.must(token_metadata).link
    end

    test "expires at return nil for patv1 with no expiry" do
      pat = make_personal_access_token(@repo_member, scopes = %w(repo))
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal pat.created_at, token_metadata&.created_at
      assert_nil token_metadata&.expires_at
      assert_nil token_metadata&.org_access
      assert_match "/settings/tokens/" + pat.id.to_s, T.must(token_metadata).link
    end

    test "returns org access for patv1" do
      pat = make_personal_access_token(@repo_member, scopes = %w(repo))
      @repo.add_member(@repo_member)
      pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @repo.organization)

      assert_equal :ORG_ACCESS, org_access
    end

    test "metadata includes whether user is suspended" do
      pat = make_personal_access_token(@suspended_repo_member, scopes = %w(repo))
      @repo.add_member(@suspended_repo_member)
      pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token

      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @repo.organization)
      metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert T.must(metadata).is_owner_suspended
      assert_equal :NO_ACCESS, org_access
    end

    test "returns no org access for patv1 when token owner does not belong to org" do
      pat = make_personal_access_token(@non_member, scopes = %w(repo))
      pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @repo.organization)

      assert_equal :NO_ACCESS, org_access
    end

    test "sso org access returned for patv1" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = pat.reset_token
      grant = Organization::CredentialAuthorization.grant(organization: token.repository.organization, credential: pat, actor: @user)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @saml_repo.organization)

      assert_equal :SSO_ACCESS, org_access
    end

    test "no sso access returned for patv1" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      grant = Organization::CredentialAuthorization.grant(organization: token.repository.organization, credential: pat, actor: @user)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @repo.organization)

      assert_equal :ORG_ACCESS, org_access
    end

    test "sso org access is false if access granted for org that does not match token org" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = pat.reset_token
      grant = Organization::CredentialAuthorization.grant(organization: @org, credential: pat, actor: @user)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @saml_repo.organization)

      assert_equal :NO_ACCESS, org_access
    end

    test "no sso access if access revoked for patv1" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = pat.reset_token
      grant = Organization::CredentialAuthorization.grant(organization: @biz_saml_org, credential: pat, actor: @user)
      revoke = Organization::CredentialAuthorization.revoke(organization: @biz_saml_org, credential: pat, actor: @user)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @saml_repo.organization)

      assert_equal :NO_ACCESS, org_access
    end

    test "org access is false if patv1 restricted" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_PERSONAL_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      @org.restrict_legacy_personal_access_tokens(actor: @user)
      token.raw_secret = pat.reset_token
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, pat.id, @repo.organization)

      assert_equal :NO_ACCESS, org_access
    end

    test "returns last accessed at when accessed" do
      pat = make_personal_access_token(@user, scopes = %w(repo))

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = pat.reset_token
      pat.update!(accessed_at: @access_date)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal pat.accessed_at, T.must(token_metadata).last_accessed_at
    end
  end

  context "#oauth_access" do
    test "metadata for oauth token" do
      oauth = make_oauth @user, ["security_events"]

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_OAUTH_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = oauth.reset_token
      oauth.update!(expires_at: @expires_at)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal oauth.created_at, token_metadata&.created_at
      assert_equal @expires_at.strftime("%B %-d, %Y"), token_metadata&.expires_at.strftime("%B %-d, %Y")
      assert_nil token_metadata&.link
    end

    test "metadata includes whether user is suspended for an oauth token" do
      oauth = make_oauth @suspended_repo_member, ["security_events"]
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_OAUTH_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = oauth.reset_token
      oauth.update!(expires_at: @expires_at)

      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert T.must(token_metadata).is_owner_suspended
      assert_equal oauth.created_at, token_metadata&.created_at
      assert_equal @expires_at.strftime("%B %-d, %Y"), token_metadata&.expires_at.strftime("%B %-d, %Y")
      assert_nil token_metadata&.link
    end

    test "metadata for user to server token" do
      integration = create :integration, default_permissions: { "metadata" => :read }
      installation = make_integration_installation(integration: integration, repository: @repo)
      user_to_server_access = installation.integration.grant(@user)

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_USER_TO_SERVER_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = user_to_server_access.reset_token
      user_to_server_access.update!(expires_at: @expires_at.to_i)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal user_to_server_access.created_at, token_metadata&.created_at
      assert_equal @expires_at.strftime("%B %-d, %Y"), token_metadata&.expires_at.strftime("%B %-d, %Y")
      assert_equal @user.id, token_metadata&.owner_id
    end

    test "metadata for user to server token includes whether user is suspended" do
      integration = create :integration, default_permissions: { "metadata" => :read }
      installation = make_integration_installation(integration: integration, repository: @repo)
      user_to_server_access = installation.integration.grant(@suspended_repo_member)

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_USER_TO_SERVER_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = user_to_server_access.reset_token
      user_to_server_access.update!(expires_at: @expires_at.to_i)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert T.must(token_metadata).is_owner_suspended
      assert_equal user_to_server_access.created_at, token_metadata&.created_at
      assert_equal @expires_at.strftime("%B %-d, %Y"), token_metadata&.expires_at.strftime("%B %-d, %Y")
      assert_equal @suspended_repo_member.id, token_metadata&.owner_id
    end

    test "metadata for user to server refresh token includes whether user is suspended" do
      integration = create :integration, default_permissions: { "metadata" => :read }
      installation = make_integration_installation(integration: integration, repository: @repo)
      user_to_server_access = installation.integration.grant(@suspended_repo_member)
      tokens = user_to_server_access.redeem

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Refresh Token",
        token_type: "GITHUB_REFRESH_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      ## tokens[0] is the user to server token, tokens[1] is the refresh token
      token.raw_secret = tokens[1]
      user_to_server_access.update!(expires_at: @expires_at.to_i)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert T.must(token_metadata).is_owner_suspended
      assert_in_delta Time.at(user_to_server_access.created_at), Time.at(token_metadata&.created_at), 1.second
      assert_equal @suspended_repo_member.id, token_metadata&.owner_id
    end

    test "org access is true for apps installed on org" do
      oauth = make_oauth @user, ["security_events"]
      app = create :oauth_application, user: @org

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_OAUTH_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = oauth.reset_token
      oauth.update!(expires_at: @expires_at)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, oauth.id, @repo.organization)

      assert_equal :ORG_ACCESS, org_access
    end

    test "no access for policy to restrict oauth token" do
      oauth = make_oauth @user, ["security_events"]
      app = create :oauth_application, user: @org

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_OAUTH_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      @org.update!(restrict_oauth_applications: true)
      token.raw_secret = oauth.reset_token
      oauth.update!(expires_at: @expires_at)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, oauth.id, @repo.organization)

      assert_equal :NO_ACCESS, org_access
    end

    test "last accessed returned for user to server token" do
      integration = create :integration, default_permissions: { "metadata" => :read }
      installation = make_integration_installation(integration: integration, repository: @repo)

      user_to_server_access = installation.integration.grant(@user)

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_USER_TO_SERVER_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = user_to_server_access.reset_token
      user_to_server_access.update!(accessed_at: @access_date)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal user_to_server_access.accessed_at, T.must(token_metadata).last_accessed_at
    end

    test "oauth returns last accessed at" do
      oauth = make_oauth @user, ["security_events"]

      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Oauth Access Token",
        token_type: "GITHUB_OAUTH_ACCESS_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = oauth.reset_token
      oauth.update!(accessed_at: @access_date)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal oauth.accessed_at, token_metadata&.last_accessed_at
    end
  end

  context "#refresh_access" do
    test "refresh returns created at" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Refresh Token",
        token_type: "GITHUB_REFRESH_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @refresh_token.reset_token(entry_point: :test_case)
      @refresh_token.update!(refreshable_id: @access.id)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal token_metadata&.created_at, @refresh_token.created_at
      assert_equal Time.at(@refresh_token.expires_at), token_metadata&.expires_at
      assert_nil token_metadata&.link
    end
  end

  context "#server_to_server" do
    test "server to server returns metadata" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub App Installation Access Token",
        token_type: "GITHUB_SERVER_TO_SERVER_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )
      expiry_time = Time.at(@record.expires_at_timestamp.to_i)
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @app_token
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal token_metadata&.created_at, @record.created_at
      assert_equal expiry_time, token_metadata&.expires_at
      assert_nil token_metadata&.link
      assert_nil token_metadata&.owner_id
    end

    test "gh app token returns metadata" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub App Installation Access Token",
        token_type: "GITHUB_APP_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @app_token
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal token_metadata&.created_at, @record.created_at
      assert_equal Time.at(@record.expires_at_timestamp.to_i), token_metadata&.expires_at
      assert_nil token_metadata&.link
      assert_nil token_metadata&.last_accessed_at
      assert_nil token_metadata&.owner_id
    end

    test "gh app token has org access" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub App Installation Access Token",
        token_type: "GITHUB_APP_TOKEN",
        repository_id: @repo.id,
        number: 1,
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @app_token_org
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @record_org.id, @repo.organization)

      assert_equal :ORG_ACCESS, org_access
    end
  end

  context "#ssh_key" do
    test "ssh key returns metadata" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @repo.id,
        number: 1,
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @private_key_contents
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal token_metadata&.created_at, @public_key.created_at
      assert_nil token_metadata&.expires_at
      assert_equal "/settings/keys", token_metadata&.link
    end

    test "ssh key metadata includes owner suspension" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @repo.id,
        number: 1,
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @private_key_contents_suspended
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal token_metadata&.created_at, @public_key_suspended.created_at
      assert_nil token_metadata&.expires_at
      assert_equal "/settings/keys", token_metadata&.link
      assert T.must(token_metadata).is_owner_suspended
    end

    test "ssh key has public access for repo member" do
      @repo.add_member(@repo_member)
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @private_key_contents
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @public_key.id, @repo.organization)

      assert_equal :ORG_ACCESS, org_access
    end

    test "deploy key link constructed properly" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @repo.id,
        number: 1,
      )

      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @private_key_contents_deploy
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal "/#{@repo.nwo}/settings/keys", token_metadata&.link
    end

    test "invalid ssh key returns nil" do
      @repo.add_member(@repo_member)
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = "i am an invalid key"
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_nil token_metadata
    end

    test "ssh key returns sso access if granted" do
      @repo.add_member(@repo_member)
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = @private_key_contents
      grant = Organization::CredentialAuthorization.grant(organization: token.repository.organization, credential: @public_key, actor: @user)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @public_key.id, @saml_repo.organization)

      assert_equal org_access, :SSO_ACCESS
    end

    test "ssh key returns no access if sso access has been revoked" do
      @repo.add_member(@repo_member)
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = @private_key_contents
      grant = Organization::CredentialAuthorization.grant(organization: token.repository.organization, credential: @public_key, actor: @user)
      revoke = Organization::CredentialAuthorization.revoke(organization: token.repository.organization, credential: @public_key, actor: @saml_repo.organization.admins.first)

      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @public_key.id, @saml_repo.organization)

      assert_equal org_access, :NO_ACCESS
    end

    test "ssh key returns no org access if sso access has not been granted" do
      @repo.add_member(@repo_member)
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "Private SSH Key",
        token_type: "GITHUB_SSH_PRIVATE_KEY",
        repository_id: @saml_repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @saml_repo)
      token.raw_secret = @private_key_contents

      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @public_key.id, @saml_repo.organization)

      assert_equal org_access, :NO_ACCESS
    end

    context "on Proxima", skip_enterprise: true do
      test "ssh key with shortcode returns metadata" do
        on_multi_tenant_enterprise(tenant: @emu_business) do
          private_key_contents1, public_key_contents1 = generate_ssh_key
          public_key1 = create(:public_key, user: @emu_user, key: public_key_contents1)
          public_key1.verify(@emu_user)
          assert_includes public_key1.fingerprint_sha256, "_#{@emu_business.shortcode}"

          private_key_contents2, public_key_contents2 = generate_ssh_key
          public_key2 = create(:public_key, user: @emu_user, key: public_key_contents2)
          public_key2.verify(@emu_user)
          public_key2.unverify(:token_scan)
          assert_includes public_key2.fingerprint_sha256, "_#{@emu_business.shortcode}"

          # user repo
          token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
            created_at: Time.parse("2022-10-21"),
            first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
            id: 1,
            label: "Private SSH Key",
            token_type: "GITHUB_SSH_PRIVATE_KEY",
            repository_id: @emu_user_repo.id,
            number: 1,
          )

          token = GitHub::TokenScanning::Service::Token.new(token_from_api, @emu_user_repo)
          token.raw_secret = private_key_contents1
          token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

          assert_equal token_metadata&.created_at, public_key1.created_at
          assert_nil token_metadata&.expires_at

          # org repo
          token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
            created_at: Time.parse("2022-10-21"),
            first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
            id: 1,
            label: "Private SSH Key",
            token_type: "GITHUB_SSH_PRIVATE_KEY",
            repository_id: @emu_org_repo.id,
            number: 1,
          )

          token = GitHub::TokenScanning::Service::Token.new(token_from_api, @emu_org_repo)
          token.raw_secret = private_key_contents2
          token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

          assert_equal token_metadata&.created_at, public_key2.created_at
          assert_nil token_metadata&.expires_at
        end
      end
    end
  end

  context "#patv2" do
    test "metadata for patv2" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_TOKEN_V2",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @patv2_token
      default_expiry = @patv2_access.created_at + 30.days
      stub_authnd_programmatic_access_verify_credentials(actor_id: @user.id, access_id: @patv2_access.id)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal @patv2_access.created_at, token_metadata&.created_at
      assert_equal default_expiry.to_i, token_metadata&.expires_at.to_i
      assert_equal @patv2_access.name, token_metadata&.name
      assert_equal "/settings/personal-access-tokens/" + @patv2_access.id.to_s, token_metadata&.link
    end

    test "metadata for patv2 includes user suspension" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_TOKEN_V2",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @patv2_token
      default_expiry = @patv2_access.created_at + 30.days
      stub_authnd_programmatic_access_verify_credentials(actor_id: @suspended_repo_member.id, access_id: @patv2_access.id)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert T.must(token_metadata).is_owner_suspended
      assert_equal @patv2_access.created_at, token_metadata&.created_at
      assert_equal default_expiry.to_i, token_metadata&.expires_at.to_i
      assert_equal @patv2_access.name, token_metadata&.name
      assert_equal "/settings/personal-access-tokens/" + @patv2_access.id.to_s, token_metadata&.link
    end

    test "metadata for patv2 last accessed at" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_TOKEN_V2",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @patv2_token
      default_expiry = @patv2_access.created_at + 30.days
      stub_authnd_programmatic_access_verify_credentials(actor_id: @user.id, access_id: @patv2_access.id)
      @patv2_access.update(accessed_at: @access_date)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal @patv2_access.created_at, token_metadata&.created_at
      assert_equal default_expiry.strftime("%B %-d, %Y"), token_metadata&.expires_at.strftime("%B %-d, %Y")
      assert_equal @access_date.strftime("%B %-d, %Y"), token_metadata&.last_accessed_at.strftime("%B %-d, %Y")
      assert_equal @patv2_access.name, token_metadata&.name
      assert_equal "/settings/personal-access-tokens/" + @patv2_access.id.to_s, token_metadata&.link
    end

    test "patv2 org link is rendered" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_TOKEN_V2",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @patv2_org_token
      make_programmatic_access_grant(
        actor: @org,
        access: @patv2_org_access,
        target: @org,
        permissions: { "metadata" => :read, "administration" => :write },
        repository_selection: :all
      )
      stub_authnd_programmatic_access_verify_credentials(actor_id: @org.id, access_id: @patv2_org_access.id)
      token_metadata = SecretScanning::Services::GitHubTokenMetadataService.new.get_github_token_metadata(token)

      assert_equal "/organizations/#{@org.name_with_display_owner}/settings/personal-access-tokens/#{@patv2_org_access.grant.id}", token_metadata&.link
    end

    test "metadata for patv2 org access" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB_TOKEN_V2",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
      token.raw_secret = @patv2_org_token
      make_programmatic_access_grant(
        actor: @org,
        access: @patv2_org_access,
        target: @org,
        permissions: { "metadata" => :read, "administration" => :write },
        repository_selection: :all
      )
      stub_authnd_programmatic_access_verify_credentials(actor_id: @org.id, access_id: @patv2_org_access.id)
      org_access = SecretScanning::Services::GitHubTokenMetadataService.new.get_org_access(token.token_type, @patv2_org_access.id, @org)

      assert_equal :ORG_ACCESS, org_access
    end
  end

  context "get_pat_recent_actions" do
    test "returns no actions if user is nil" do
      token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
        created_at: Time.parse("2022-10-21"),
        first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
        id: 1,
        label: "GitHub Personal Access Token",
        token_type: "GITHUB",
        repository_id: @repo.id,
        number: 1,
      )
      token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)

      actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(token, nil)

      assert_empty actions
    end

    context "patv1" do
      test "returns recent actions created by the token in the owner of the repo in which it was found" do
        pat = make_personal_access_token(@repo_member, scopes = %w(repo))
        pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = pat.reset_token
        actions = ["action_type_1", "action_type_1", "action_type_3", "personal_access_token.create", "action_type_1"]
        es_results = Search::Results.new({ "hits" => { "hits" => actions.map { |a| MockAuditResult.new(action: a) }, "total" => 5 } }, { page: 1, per_page: 10 })
        Search::Queries::AuditLogQuery.any_instance.stubs(:execute).returns(es_results)

        actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(token, @user)

        expected_actions = %w[action_type_1 action_type_1 action_type_3 action_type_1]
        assert_equal expected_actions, actions
      end
    end
    context "patv2" do
      test "returns recent actions for an org scoped token" do
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB_TOKEN_V2",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = @patv2_org_token
        make_programmatic_access_grant(
          actor: @org,
          access: @patv2_org_access,
          target: @org,
          permissions: { "administration" => :write, "actions" => :read, "codespaces" => :read },
          repository_selection: :all
        )
        stub_authnd_programmatic_access_verify_credentials(actor_id: @org.id, access_id: @patv2_org_access.id)
        actions = ["action_type_1", "action_type_1", "action_type_3", "personal_access_token.create", "action_type_1"]
        es_results = Search::Results.new({ "hits" => { "hits" => actions.map { |a| MockAuditResult.new(action: a) }, "total" => 5 } }, { page: 1, per_page: 10 })
        Search::Queries::AuditLogQuery.any_instance.stubs(:execute).returns(es_results)

        actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(token, @user)

        expected_actions = %w[action_type_1 action_type_1 action_type_3 action_type_1]
        assert_equal expected_actions, actions
      end

      test "returns recent actions for a user scoped token" do
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB_TOKEN_V2",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = @patv2_token
        default_expiry = @patv2_access.created_at + 30.days
        make_programmatic_access_grant(
          actor: @user,
          access: @patv2_access,
          target: @user,
          permissions: { "metadata" => :read, "administration" => :write },
          repository_selection: :all
        )
        stub_authnd_programmatic_access_verify_credentials(actor_id: @user.id, access_id: @patv2_access.id)
        actions = ["action_type_1", "action_type_1", "action_type_3", "personal_access_token.create", "action_type_1"]
        es_results = Search::Results.new({ "hits" => { "hits" => actions.map { |a| MockAuditResult.new(action: a) }, "total" => 5 } }, { page: 1, per_page: 10 })
        Search::Queries::AuditLogQuery.any_instance.stubs(:execute).returns(es_results)

        actions = SecretScanning::Services::GitHubTokenMetadataService.new.get_pat_recent_actions(token, @user)

        expected_actions = %w[action_type_1 action_type_1 action_type_3 action_type_1]
        assert_equal expected_actions, actions
      end
    end
  end

  context "permissions" do
    context "fgp" do
      test "gets org permissions" do
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB_TOKEN_V2",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = @patv2_org_token
        make_programmatic_access_grant(
          actor: @org,
          access: @patv2_org_access,
          target: @org,
          permissions: { "administration" => :write, "actions" => :read, "codespaces" => :read },
          repository_selection: :all
        )
        stub_authnd_programmatic_access_verify_credentials(actor_id: @org.id, access_id: @patv2_org_access.id)

        permissions = SecretScanning::Services::GitHubTokenMetadataService.new.get_fgp_permissions(token)

        assert_equal "write", T.must(permissions).permissions["administration"]
        assert_equal "read", T.must(permissions).permissions["codespaces"]
        assert_equal "read", T.must(permissions).permissions["actions"]
        assert_equal "read", T.must(permissions).permissions["metadata"] #mandatory
      end

      test "gets user permissions" do
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB_TOKEN_V2",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = @patv2_token
        default_expiry = @patv2_access.created_at + 30.days
        make_programmatic_access_grant(
          actor: @user,
          access: @patv2_access,
          target: @user,
          permissions: { "metadata" => :read, "administration" => :write },
          repository_selection: :all
        )
        stub_authnd_programmatic_access_verify_credentials(actor_id: @user.id, access_id: @patv2_access.id)

        permissions = SecretScanning::Services::GitHubTokenMetadataService.new.get_fgp_permissions(token)

        assert_equal "write", T.must(permissions).permissions["administration"]
        assert_equal "read", T.must(permissions).permissions["metadata"]
      end
    end

    context "patv1" do
      test "gets permissions for patv1" do
        pat = make_personal_access_token(@repo_member, scopes = %w(repo:status repo_deployment admin:org admin:public_key gist notifications))
        pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = pat.reset_token

        permissions = SecretScanning::Services::GitHubTokenMetadataService.new.get_patv1_permissions(token)

        expected_with_parents = {
          "repo" => ["repo:status", "repo_deployment"],
          "org" => ["admin:org", "manage_runners:org", "write:org", "read:org"],
          "public_key" => ["admin:public_key", "write:public_key", "read:public_key"],
          "gist" => ["gist"],
          "notifications" => ["notifications"]
        }
        expected_all_perms = ["repo:status", "repo_deployment", "admin:org", "manage_runners:org", "write:org", "read:org", "admin:public_key", "write:public_key", "read:public_key", "gist", "notifications"]
        assert_equal expected_all_perms, T.must(permissions).all_scopes
        assert_equal expected_with_parents, T.must(permissions).scopes_with_parents
      end

      test "no permissions for pat created with no scopes" do
        pat = make_personal_access_token(@repo_member, scopes = %w())
        assert_empty pat.scopes
        pat.update!(expires_at_timestamp: @expires_at, description: "PAT Name")
        token_from_api = GitHub::Proto::SecretScanning::Api::V2::Token.new(
          created_at: Time.parse("2022-10-21"),
          first_location: GitHub::Proto::SecretScanning::Api::V2::TokenLocation.new(created_at: Time.parse("2022-10-21")),
          id: 1,
          label: "GitHub Personal Access Token",
          token_type: "GITHUB",
          repository_id: @repo.id,
          number: 1,
        )
        token = GitHub::TokenScanning::Service::Token.new(token_from_api, @repo)
        token.raw_secret = pat.reset_token

        permissions = SecretScanning::Services::GitHubTokenMetadataService.new.get_patv1_permissions(token)

        expected_with_parents = {}
        assert_equal [], T.must(permissions).all_scopes
        assert_equal expected_with_parents, T.must(permissions).scopes_with_parents
      end
    end
  end
end

class MockAuditResult < T::Struct
  attr_accessor :results

  const :action, String
end
