# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRemoteAuthenticationDependencyTest < GitHub::TestCase
  fixtures do
    @subject = create(:user)
  end

  context "#using_basic_auth?" do
    test "returns true by default" do
      assert_predicate @subject, :using_basic_auth?
    end

    test "return false if the user can't authenticate via basic auth" do
      @subject.stubs(:can_authenticate_via_username_password_basic_auth?).returns(false)
      refute_predicate @subject, :using_basic_auth?
    end

    test "returns false if :oauth_access is set on the user" do
      @subject.oauth_access = :foo
      refute_predicate @subject, :using_basic_auth?
    end

    test "returns false if :scopes are set on the user" do
      @subject.scopes = []
      refute_predicate @subject, :using_basic_auth?
    end

    test "returns false if :programmatic_access is set on the user" do
      @subject.programmatic_access = :foo
      refute_predicate @subject, :using_basic_auth?
    end
  end

  context "#using signed auth token" do
    test "generating signed auth token" do
      token = @subject.signed_auth_token scope: "some_scope"

      authed_user = User.authenticate_with_signed_auth_token scope: "some_scope", token: token
      assert_equal @subject, authed_user

      parsed_token = User.verify_signed_auth_token scope: "some_scope", token: token
      assert_equal @subject, parsed_token.user
      assert_equal "some_scope", parsed_token.scope
      assert parsed_token.valid?
    end

    test "signed auth tokens with wrong scope don't authenticate" do
      token = @subject.signed_auth_token scope: "some_scope"
      assert_nil User.authenticate_with_signed_auth_token scope: "bad_scope", token: token
    end

    test "expired signed auth tokens don't authenticate" do
      token = @subject.signed_auth_token scope: "some_scope", expires: 30.seconds.ago
      assert_nil User.authenticate_with_signed_auth_token scope: "some_scope", token: token
    end

    test "evaluate signed auth token presence in user" do
      token = @subject.signed_auth_token scope: "some_scope"

      authed_user = User.authenticate_with_signed_auth_token scope: "some_scope", token: token
      assert_equal @subject, authed_user
      assert authed_user.using_auth_via_signed_auth_token?
      assert_nil authed_user.sat_context.user

      parsed_token = User.verify_signed_auth_token scope: "some_scope", token: token
      assert_equal @subject, parsed_token.user
      assert parsed_token.valid?
      assert parsed_token.user.using_auth_via_signed_auth_token?
      assert_nil parsed_token.user.sat_context.user
    end

    test "evaluate signed auth token presence in user invalid token" do
      token = @subject.signed_auth_token scope: "some_scope"
      assert_nil User.authenticate_with_signed_auth_token scope: "bad_scope", token: token
      refute @subject.using_auth_via_signed_auth_token?

      token = @subject.signed_auth_token scope: "some_scope", expires: 30.seconds.ago
      assert_nil User.authenticate_with_signed_auth_token scope: "some_scope", token: token
      refute @subject.using_auth_via_signed_auth_token?

      session = create :user_session, user: @subject
      verified_token = GitHub::Authentication::GitAuth::SignedAuthToken.verify(token: token, scope: "some_scope")
      refute verified_token.valid?
      assert_nil verified_token.user
    end
  end

  test "is allowed via basic auth" do
    assert_predicate @subject, :can_authenticate_via_basic_auth?
  end

  test "is allowed via username and password basic auth" do
    assert_predicate @subject, :can_authenticate_via_username_password_basic_auth?
  end

  test "User#using_oauth? should be false with username password auth" do
    user, message = User.authenticate(@subject, GitHub.default_password)
    assert_equal @subject, user
    refute user.using_oauth?
  end

  context "programmatic_ability_delegate_for_repository" do
    test "returns installation when installed on repo" do
      repo = create(:private_repository, :minimal, owner: @subject)
      integration = create(:integration, default_permissions: { "contents" => :read })
      access = integration.grant(@subject, entry_point: :test_case)
      @subject.oauth_access = access

      expected_installation = integration.install_on(
        @subject, repositories: [repo],
        version: integration.latest_version,
        installer: @subject,
        entry_point: :test_case).installation

      actual_installation = @subject.programmatic_ability_delegate_for_repository(repo)

      assert_equal expected_installation, actual_installation
    end

    test "returns installation when installed globally" do
      repo = create(:private_repository, :minimal)
      integration = create_privileged_app_with_capabilities(
        capabilities: { installed_globally: true }
      )
      access = integration.grant(@subject, entry_point: :test_case)
      @subject.oauth_access = access

      expected_installation = GlobalIntegrationInstallation.new(integration, repo.owner)
      actual_installation = @subject.programmatic_ability_delegate_for_repository(repo)

      assert_equal expected_installation.class, actual_installation.class
      assert_equal expected_installation.integration, actual_installation.integration
      assert_equal expected_installation.target, actual_installation.target
    end
  end

  context "installation fallback to primary" do
    test "loads the SiteScopedIntegrationInstallation from primary if not found on replica" do
      enable_feature_flag(:signed_auth_token_installation_fallback_to_primary)
      disable_feature_flag(:disabled_global_apps)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      ActiveRecord::Base.stubs(:connected_to?).returns(true)

      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      integration = create_unlimited_global_integration
      installation = make_site_scoped_integration_installation(integration: integration, target: org, repositories: [repo])

      stubbed_installation = stub
      SiteScopedIntegrationInstallation.stubs(:includes).returns(stubbed_installation)
      stubbed_installation.stubs(:find_by).returns(nil).then.returns(installation) # return nil on first call, installation on second call

      token = installation.bot.signed_auth_token(scope: "some_scope")
      authed_user = User.authenticate_with_signed_auth_token scope: "some_scope", token: token

      assert_equal installation.bot, authed_user
      assert_equal installation, authed_user.installation
      assert_equal 1, GitHub.dogstats.increments("signed_auth_token.installation.fallback_to_primary", tags: ["installation_type:SiteScopedIntegrationInstallation", "found_on_primary:true"]).count
    end

    test "loads the ScopedIntegrationInstallation from primary if not found on replica" do
      enable_feature_flag(:signed_auth_token_installation_fallback_to_primary)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      ActiveRecord::Base.stubs(:connected_to?).returns(true)

      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      parent = make_integration_installation(target: org)
      installation = make_scoped_integration_installation(parent: parent, repositories: [repo])

      stubbed_installation = stub
      ScopedIntegrationInstallation.stubs(:includes).returns(stubbed_installation)
      stubbed_installation.stubs(:find_by).returns(nil).then.returns(installation) # return nil on first call, installation on second call

      token = installation.bot.signed_auth_token(scope: "some_scope")
      authed_user = User.authenticate_with_signed_auth_token scope: "some_scope", token: token

      assert_equal installation.bot, authed_user
      assert_equal installation, authed_user.installation
      assert_equal 1, GitHub.dogstats.increments("signed_auth_token.installation.fallback_to_primary", tags: ["installation_type:ScopedIntegrationInstallation", "found_on_primary:true"]).count
    end

    test "loads the IntegrationInstallation from primary if not found on replica" do
      enable_feature_flag(:signed_auth_token_installation_fallback_to_primary)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      ActiveRecord::Base.stubs(:connected_to?).returns(true)

      org = create(:organization)
      repo = create(:private_repository, :minimal, owner: org)
      installation = make_integration_installation(target: org, repositories: [repo])

      stubbed_installation = stub
      IntegrationInstallation.stubs(:includes).returns(stubbed_installation)
      stubbed_installation.stubs(:find_by).returns(nil).then.returns(installation) # return nil on first call, installation on second call

      token = installation.bot.signed_auth_token(scope: "some_scope")
      authed_user = User.authenticate_with_signed_auth_token scope: "some_scope", token: token

      assert_equal installation.bot, authed_user
      assert_equal installation, authed_user.installation
      assert_equal 1, GitHub.dogstats.increments("signed_auth_token.installation.fallback_to_primary", tags: ["installation_type:IntegrationInstallation", "found_on_primary:true"]).count
    end
  end
end
