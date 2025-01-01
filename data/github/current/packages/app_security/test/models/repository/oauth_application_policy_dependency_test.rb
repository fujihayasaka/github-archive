# typed: true
# frozen_string_literal: true

require "test_helper"

class DeterminingRepositoryAccessBasedOnOAuthAppPolicyTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner

    @user = create :user, login: "a-user", plan: "micro"
    @forking_user = create :user, login: "forking-user"
    @org = create :organization, login: "an-org", admin: @user, plan: "bronze"
    @org.allow_private_repository_forking(actor: @user, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @forking_org = create :organization, login: "forking-org", admin: @forking_user

    @third_party_app = create :oauth_application, name: "3rd party app"
    @org_app = create :oauth_application, user: @org, name: "Org owned app"
    @forking_org_app = create :oauth_application, user: @forking_org

    #
    # Set up user-owned repo network

    @user_repo = create :private_repository, owner: @user
    @user_repo.add_member(@forking_user)

    @user_fork_of_user_repo, status = @user_repo.fork(forker: @forking_user)
    assert_equal :created, status
    assert_equal @user, @user_fork_of_user_repo.root.owner

    @org_fork_of_user_repo, status =
      @user_repo.fork(forker: @forking_user, org: @forking_org)
    assert_equal :created, status
    assert_equal @user, @org_fork_of_user_repo.root.owner

    @repos_in_user_repo_network = [
      @user_repo,
      @user_fork_of_user_repo,
      @org_fork_of_user_repo,
    ]
    #
    # Set up org-owned private repo network

    @private_org_repo = create :private_repository, owner: @org
    org_team = create(:team, organization: @org)
    org_team.add_member(@forking_user)
    org_team.add_repository(@private_org_repo, :pull)

    @user_fork_of_private_org_repo, status = @private_org_repo.fork(forker: @forking_user)
    assert_equal :created, status
    assert_equal @org, @user_fork_of_private_org_repo.root.owner

    @org_fork_of_private_org_repo, status =
      @private_org_repo.fork(forker: @forking_user, org: @forking_org)
    assert_equal :created, status
    assert_equal @org, @org_fork_of_private_org_repo.root.owner

    @repos_in_org_private_repo_network = [
      @private_org_repo,
      @user_fork_of_private_org_repo,
      @org_fork_of_private_org_repo,
    ]

    #
    # Set up org-owned public repo network

    @public_org_repo = create(:public_repository, owner: @org)
    org_team = create(:team, organization: @org)
    org_team.add_member(@forking_user)
    org_team.add_repository(@public_org_repo, :pull)

    @user_fork_of_public_org_repo, status = @public_org_repo.fork(forker: @forking_user)
    assert_equal :created, status
    assert_equal @org, @user_fork_of_public_org_repo.root.owner

    @org_fork_of_public_org_repo, status =
      @public_org_repo.fork(forker: @forking_user, org: @forking_org)
    assert_equal :created, status
    assert_equal @org, @org_fork_of_public_org_repo.root.owner
  end

  context "user-owned repository network" do
    test "app allowed" do
      assert_network_oauth_app_policy_met \
        @third_party_app, @repos_in_user_repo_network
    end

    # see: https://github.com/github/security/issues/2956
    test "excludes org-owned private fork when OAP is enabled for an unapproved app" do
      @forking_org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met \
        @third_party_app, [@user_repo, @user_fork_of_user_repo]

    end

    # see: https://github.com/github/security/issues/2956
    test "includes org-owned private fork when OAP is enabled for an approved app" do
      @forking_org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met \
        @third_party_app, [@user_repo, @user_fork_of_user_repo]


      @forking_org.approve_oauth_application(@third_party_app, approver: @forking_user)

      assert_network_oauth_app_policy_met \
        @third_party_app, [@user_repo, @user_fork_of_user_repo, @org_fork_of_user_repo]

    end
  end

  context "org-owned private repository network" do
    # If the repo is private:
    # - owner and network owner is an organization and:
    # - owner *does* restrict apps, and there's authorization
    # - network owner *does* restrict apps, and there's no authorization
    test "3rd-party app blocked when network owner does restrict apps and there's an approval on the forked repo" do
      @org.enable_oauth_application_restrictions
      @forking_org.enable_oauth_application_restrictions

      @forking_org.approve_oauth_application(@third_party_app, approver: @forking_user)

      refute_network_oauth_app_policy_met @third_party_app, [@org_fork_of_private_org_repo]
    end

    # If the repo is private:
    # - owner and network owner is an organization and:
    # - owner *does* restrict apps, and there's no authorization
    # - network owner *does* restrict apps, and there's authorization
    test "3rd-party app blocked when network owner does restrict apps and there's no approval on the forked repo" do
      @org.enable_oauth_application_restrictions
      @forking_org.enable_oauth_application_restrictions

      @org.approve_oauth_application(@third_party_app, approver: @user)

      refute_network_oauth_app_policy_met @third_party_app, [@org_fork_of_private_org_repo]
    end

    # If the repo is private:
    # - owner and network owner is an organization and:
    # - owner *does* restrict apps, and there's no authorization
    # - network owner *does not* restrict apps
    test "3rd-party app blocked when owner does restrict apps but network owner does not restrict apps" do
      @forking_org.enable_oauth_application_restrictions

      refute_network_oauth_app_policy_met @third_party_app, [@org_fork_of_private_org_repo]
    end

    test "3rd-party app allowed when network owner does not restrict apps" do
      assert_network_oauth_app_policy_met \
        @third_party_app, @repos_in_org_private_repo_network
    end

    test "unapproved 3rd-party app blocked when network owner restricts apps" do
      @org.enable_oauth_application_restrictions

      refute_network_oauth_app_policy_met \
        @third_party_app, @repos_in_org_private_repo_network
    end

    test "pending-approval 3rd-party app blocked when network owner restricts apps" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@third_party_app, requestor: @user)

      refute_network_oauth_app_policy_met \
        @third_party_app, @repos_in_org_private_repo_network
    end

    test "approved 3rd-party app allowed when network owner restricts apps" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@third_party_app, approver: @user)

      assert_network_oauth_app_policy_met \
        @third_party_app, @repos_in_org_private_repo_network
    end

    test "denied 3rd-party app blocked when network owner restricts apps" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@third_party_app, requestor: @user)
      @org.deny_oauth_application(@third_party_app, actor: @user)

      refute_network_oauth_app_policy_met \
        @third_party_app, @repos_in_org_private_repo_network
    end

    test "network owner app allowed when network owner does not restrict apps" do
      assert_network_oauth_app_policy_met \
        @org_app, @repos_in_org_private_repo_network
    end

    test "network owner app allowed when network owner restricts apps" do
      @org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met \
        @org_app, @repos_in_org_private_repo_network
    end

    test "GitHub owned app not allowed when owner restricts apps" do
      github_app = create :oauth_application, \
        user: GitHub.trusted_oauth_apps_owner,
        name: "GitHub owned app"

      @org.enable_oauth_application_restrictions

      refute_network_oauth_app_policy_met \
        github_app, @repos_in_org_private_repo_network
    end

    test "capable internal apps allowed when owner restricts apps" do
      internal_app = create :oauth_application
      Apps::Privileged::Registry.configure(
        app_alias: :exempt_oauth_app,
        app: internal_app,
        id: ->() { internal_app.id },
        capabilities: {
          organization_oauth_app_policy_exempt: true
        }
      )
      assert internal_app.third_party_oap_exempt?

      @org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met \
        internal_app, @repos_in_org_private_repo_network
    end

    test "capable internal apps don't violate oauth app policy" do
      internal_app = create :oauth_application
      Apps::Privileged::Registry.configure(
        app_alias: :exempt_oauth_app,
        app: internal_app,
        id: ->() { internal_app.id },
        capabilities: {
          organization_oauth_app_policy_exempt: true
        }
      )

      assert internal_app.third_party_oap_exempt?

      violated = Repository.oauth_app_policy_violated_repository_ids(
        repository_scope: @user.repositories,
        app: internal_app,
      )
      assert_equal [], violated
    end

    test "GitHub desktop apps allowed by default when owner restricts apps but not when blocked" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable

      make_trusted_oauth_apps_owner
      oauth_app = create :github_desktop_app

      # Extra asserts to debug CI
      assert oauth_app.github_owned?
      assert oauth_app.blockable_client_app?
      assert oauth_app.third_party_oap_exempt?

      @org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network

      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      refute_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network
    end

    test "considers first_party_oauth_app_restrictions feature flag for org" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable
      GitHub.flipper[:first_party_oauth_app_restrictions].disable # Disable FF for all

      make_trusted_oauth_apps_owner
      oauth_app = create :blockable_oauth_app
      @org.enable_oauth_application_restrictions

      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      refute_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network

      GitHub.flipper[:first_party_oauth_app_restrictions].disable(@org)

      # block is ignored bc ff isn't enabled
      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network, skip_org_check: true
    end

    test "does not consider first_party_oauth_app_restrictions feature flag for business when consider_business_oap_ff FF is disabled" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable
      GitHub.flipper[:first_party_oauth_app_restrictions].disable # Disable main FF for all

      # Create blockable app
      make_trusted_oauth_apps_owner
      oauth_app = create :blockable_oauth_app

      # Enable OAP restrictions
      @org.enable_oauth_application_restrictions

      # Create business for org
      @org.business = create(:business)
      @org.save!

      # Do not consider businesses when checking for first_party_oauth_app_restrictions
      GitHub.flipper[:consider_business_oap_ff].disable

      # Enable main FF for business
      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org.business)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

      # Block app by org
      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network, skip_org_check: true
    end

    test "considers first_party_oauth_app_restrictions feature flag for business when consider_business_oap_ff FF is enabled" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable
      GitHub.flipper[:first_party_oauth_app_restrictions].disable # Disable main FF for all

      # Create blockable app
      make_trusted_oauth_apps_owner
      oauth_app = create :blockable_oauth_app

      # Enable OAP restrictions
      @org.enable_oauth_application_restrictions

      # Create business for org
      @org.business = create(:business)
      @org.save!

      # Consider businesses when checking for first_party_oauth_app_restrictions
      GitHub.flipper[:consider_business_oap_ff].enable

      # Enable main FF for business
      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org.business)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

      # Block app by org
      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      refute_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network

      GitHub.flipper[:first_party_oauth_app_restrictions].disable(@org.business)

      # block is ignored bc ff isn't enabled
      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network, skip_org_check: true
    end

    test "considers blockable_apps_not_exempt feature flag" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable

      make_trusted_oauth_apps_owner
      oauth_app = create :github_desktop_app
      assert oauth_app.blockable_client_app?
      @org.enable_oauth_application_restrictions

      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      refute_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network

      GitHub.flipper[:blockable_apps_not_oap_exempt].disable
      # block is ignored bc ff isn't enabled for org
      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network
    end

    test "considers load_approved_orgs_first_party_app feature flag" do
      GitHub.flipper[:blockable_apps_not_oap_exempt].enable
      GitHub.flipper[:load_approved_orgs_first_party_oap].enable

      make_trusted_oauth_apps_owner
      oauth_app = create :blockable_oauth_app
      @org.enable_oauth_application_restrictions

      GitHub.flipper[:first_party_oauth_app_restrictions].enable(@org)
      Organization.any_instance.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      block = create(:oauth_application_approval, organization: @org, application: oauth_app, state: :blocked)

      refute_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network

      GitHub.flipper[:load_approved_orgs_first_party_oap].disable

      # block is ignored bc ff isn't enabled
      assert_network_oauth_app_policy_met \
        oauth_app, @repos_in_org_private_repo_network, skip_org_check: true
    end
  end

  context "org-owned public repository network" do
    test "3rd-party app can access root when root owner does not restrict apps" do
      assert_network_oauth_app_policy_met @third_party_app, @public_org_repo
    end

    test "3rd-party app can access org-owned fork when fork owner does not restrict apps" do
      assert_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
    end

    test "3rd-party app cannot access root when root owner restricts apps and has not approved the app" do
      @org.enable_oauth_application_restrictions
      refute_network_oauth_app_policy_met @third_party_app, @public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@org_fork_of_public_org_repo, @user_fork_of_public_org_repo]
    end

    test "3rd-party app cannot access org-owned fork when fork owner restricts apps and has not approved the app" do
      @forking_org.enable_oauth_application_restrictions
      refute_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@public_org_repo, @user_fork_of_public_org_repo]
    end

    test "3rd-party app cannot access root when root owner restricts apps and the app is pending approval" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@third_party_app, requestor: @user)

      refute_network_oauth_app_policy_met @third_party_app, @public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@org_fork_of_public_org_repo, @user_fork_of_public_org_repo]
    end

    test "3rd-party app cannot access org-owned fork when fork owner restricts apps and the app is pending approval" do
      @forking_org.enable_oauth_application_restrictions
      @forking_org.request_oauth_application_approval(@third_party_app, requestor: @forking_user)

      refute_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@public_org_repo, @user_fork_of_public_org_repo]
    end

    test "3rd-party app can access root when root owner restricts apps and has approved the app" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@third_party_app, approver: @user)

      assert_network_oauth_app_policy_met @third_party_app, @public_org_repo
    end

    test "3rd-party app can access org-owned fork when fork owner restricts apps and has approved the app" do
      @forking_org.enable_oauth_application_restrictions
      @forking_org.approve_oauth_application(@third_party_app, approver: @forking_user)

      assert_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
    end

    test "3rd-party app cannot automatically access org-owned fork when root owner restricts apps and has approved the app" do
      # Block all apps for fork owner
      @forking_org.enable_oauth_application_restrictions

      # Approve app for root owner
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@third_party_app, approver: @user)

      refute_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
    end

    test "3rd-party app cannot automatically access root when fork owner restricts apps and has approved the app" do
      # Block all apps for root owner
      @org.enable_oauth_application_restrictions

      # Approve app for fork owner
      @forking_org.enable_oauth_application_restrictions
      @forking_org.approve_oauth_application(@third_party_app, approver: @forking_user)

      refute_network_oauth_app_policy_met @third_party_app, @public_org_repo
    end

    test "3rd-party app cannot access root when root owner restricts apps and the app is denied" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@third_party_app, requestor: @user)
      @org.deny_oauth_application(@third_party_app, actor: @user)

      refute_network_oauth_app_policy_met @third_party_app, @public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@org_fork_of_public_org_repo, @user_fork_of_public_org_repo]
    end

    test "3rd-party app cannot access org-owned fork when fork owner restricts apps and the app is denied" do
      @forking_org.enable_oauth_application_restrictions
      @forking_org.request_oauth_application_approval(@third_party_app, requestor: @forking_user)
      @forking_org.deny_oauth_application(@third_party_app, actor: @user)

      refute_network_oauth_app_policy_met @third_party_app, @org_fork_of_public_org_repo
      assert_network_oauth_app_policy_met \
        @third_party_app, [@public_org_repo, @user_fork_of_public_org_repo]
    end

    test "root owner's app can access root when root owner does not restrict apps" do
      assert_network_oauth_app_policy_met @org_app, @public_org_repo
    end

    test "fork owner's app can access org-owned fork when fork owner does not restrict apps" do
      assert_network_oauth_app_policy_met @forking_org_app, @org_fork_of_public_org_repo
    end

    test "root owner's app can access root when root owner restricts apps" do
      @org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met @org_app, @public_org_repo
    end

    test "fork owner's app can access org-owned fork when fork owner restricts apps" do
      @forking_org.enable_oauth_application_restrictions

      assert_network_oauth_app_policy_met @forking_org_app, @org_fork_of_public_org_repo
    end

    test "root owner's app cannot automatically access org-owned fork when fork owner restricts apps" do
      # Block all third-party apps for fork owner
      @forking_org.enable_oauth_application_restrictions

      # Block all third-party apps for root owner
      @org.enable_oauth_application_restrictions

      refute_network_oauth_app_policy_met @org_app, @org_fork_of_public_org_repo
    end

    test "fork owner's app cannot automatically access root when root owner restricts apps" do
      # Block all third-party apps for root owner
      @org.enable_oauth_application_restrictions

      # Block all third-party apps for fork owner
      @forking_org.enable_oauth_application_restrictions

      refute_network_oauth_app_policy_met @forking_org_app, @public_org_repo
    end
  end

  def assert_network_oauth_app_policy_met(app, repos, skip_org_check: false)
    Array(repos).map(&:reload).each do |repo|
      # Verify AR scopes
      assert_includes Repository.oauth_app_policy_approved_repository_ids(
        repository_ids: Repository.ids, app: app,
      ), repo.id
      refute_includes Repository.oauth_app_policy_violated_repository_ids(
        repository_ids: Repository.ids, app: app,
      ), repo.id

      # Verify this repo knows that this app satisfies the policy
      assert OauthApplicationPolicy::Application.new(repo, app).satisfied?,
        "#{app.name} did not meet application policy for org: #{repo.owner.display_login}" unless skip_org_check
    end
  end

  def refute_network_oauth_app_policy_met(app, repos)
    Array(repos).map(&:reload).each do |repo|
      # Verify AR scopes
      refute_includes Repository.oauth_app_policy_approved_repository_ids(
        repository_ids: Repository.ids, app: app,
      ), repo.id
      assert_includes Repository.oauth_app_policy_violated_repository_ids(
        repository_ids: Repository.ids, app: app,
      ), repo.id

      # Verify this repo knows that this app violates the policy
      assert OauthApplicationPolicy::Application.new(repo, app).violated?
    end
  end
end
