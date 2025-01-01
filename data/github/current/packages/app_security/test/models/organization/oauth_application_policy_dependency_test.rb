# typed: true
# frozen_string_literal: true

require "test_helper"

class OAuthApplicationPolicyDefaultsTest < GitHub::TestCase
  if GitHub.oauth_application_policies_enabled?
    test "oauth app restrictions are enabled by default for new orgs" do
      org = Organization.create! login: "an-org",
                                 organization_billing_email: "cream@example.com",
                                 admin: create(:user)

      assert_predicate org, :restricts_oauth_applications?
    end
  else
    test "oauth app restrictions are disabled by default for new orgs" do
      org = Organization.create! login: "an-org",
                                 organization_billing_email: "cream@example.com",
                                 admin: create(:user)

      refute_predicate org, :restricts_oauth_applications?
    end
  end
end

class OAuthApplicationPolicyManagementTest < GitHub::TestCase

  include DogstatsTestHelpers

  fixtures do
    @owner  = create :user, login: "owner"
    @rando  = create :user, login: "rando"

    @org = create :organization, admin: @owner
    @other_org = create :organization, admin: @owner, login: "other-org"

    @app       = make_oauth_app @rando
    @org_app   = create :oauth_application, user: @org
    @other_app = create :oauth_application, user: @org

    @github = create(:organization, login: "github")

    @github_app = create :oauth_application, \
      user: GitHub.trusted_oauth_apps_owner
    @github_desktop_app = create :oauth_application, \
      user: GitHub.trusted_oauth_apps_owner,
      key: Apps::Privileged::GitHubForMac::GITHUB_MAC_CLIENT_ID

    @access       = create :oauth_access, user: @owner, application: @app
    @other_access = create :oauth_access, user: @owner, application: @other_app
  end

  setup do
    Apps::Privileged::Registry.instance.reload_caches!
  end

  test "can enable oauth app restrictions for the org" do
    @org.enable_oauth_application_restrictions
    assert @org.restricts_oauth_applications?
  end

  test "can disable app restrictions for the org" do
    @org.enable_oauth_application_restrictions
    @org.disable_oauth_application_restrictions
    refute @org.restricts_oauth_applications?
  end

  test "instruments oauth application approval request" do
    events = subscribe "org.oauth_app_access_requested"

    @org.enable_oauth_application_restrictions
    @org.request_oauth_application_approval(@app, requestor: @owner)

    expected_payload = {
      application_name: @app.name,
      application_id: @app.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "org.oauth_app_access_requested", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments oauth application approval" do
    events = subscribe "org.oauth_app_access_approved"

    @org.enable_oauth_application_restrictions
    @org.request_oauth_application_approval(@app, requestor: @rando)
    @org.approve_oauth_application(@app, approver: @owner)

    expected_payload = {
      application_name: @app.name,
      application_id: @app.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "org.oauth_app_access_approved", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments oauth application denial" do
    events = subscribe "org.oauth_app_access_denied"

    @org.enable_oauth_application_restrictions
    @org.request_oauth_application_approval(@app, requestor: @owner)
    @org.deny_oauth_application(@app, actor: @owner)

    expected_payload = {
      actor: @owner.login,
      actor_id: @owner.id,
      application_name: @app.name,
      application_id: @app.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "an event was expected"
    assert_equal "org.oauth_app_access_denied", event.name
    assert_equal expected_payload, event.payload
  end

  test "instruments oauth application block" do
    @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
    @app.stubs(:blockable_client_app?).returns(true)

    events = subscribe "org.oauth_app_access_blocked"
    @org.block_oauth_application(application: @app, actor: @owner)

    expected_payload = {
      application_name: @app.name,
      application_id: @app.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "an event was expected"
    assert_same_hash expected_payload, event.payload
  end

  test "instruments oauth application unblock when already blocked" do
    @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
    @app.stubs(:blockable_client_app?).returns(true)
    @org.block_oauth_application(application: @app, actor: @owner)

    events = subscribe "org.oauth_app_access_unblocked"

    @org.unblock_oauth_application(application: @app, actor: @owner)

    expected_payload = {
      application_name: @app.name,
      application_id: @app.id,
      org: @org.login,
      org_id: @org.id,
    }

    assert event = events.pop, "an event was expected"
    assert_same_hash expected_payload, event.payload
  end

  test "cleans up approvals when org is destroyed" do
    @org.enable_oauth_application_restrictions
    @org.request_oauth_application_approval(@app, requestor: @owner)

    @other_org.enable_oauth_application_restrictions
    @other_org.request_oauth_application_approval(@app, requestor: @owner)

    assert_equal 1, OauthApplicationApproval.where(organization_id: @org.id).count
    assert_equal 1, OauthApplicationApproval.where(organization_id: @other_org.id).count

    @org.destroy

    assert_equal 0, OauthApplicationApproval.where(organization_id: @org.id).count
    assert_equal 1, OauthApplicationApproval.where(organization_id: @other_org.id).count
  end

  test "cleans up approvals when OAuth app is destroyed" do
    other_app = create :oauth_application, user: @rando
    @org.enable_oauth_application_restrictions
    @org.request_oauth_application_approval(@app, requestor: @owner)
    @org.request_oauth_application_approval(other_app, requestor: @owner)

    assert_equal 1, OauthApplicationApproval.where(application_id: @app.id).count
    assert_equal 1, OauthApplicationApproval.where(application_id: other_app.id).count

    @app.destroy

    assert_equal 0, OauthApplicationApproval.where(application_id: @app.id).count
    assert_equal 1, OauthApplicationApproval.where(application_id: other_app.id).count
  end

  context "#request_oauth_application_approval" do
    test "creates a pending approval for a third-party app" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @rando)

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first!

      assert approval
      assert_predicate approval, :pending_approval?
      assert_equal @rando, approval.requestor
      assert_includes @org.oauth_applications_requesting_approval, @app
      assert_includes @org.oauth_applications_requesting_approval(state: :pending), @app
      refute_includes @org.oauth_applications_requesting_approval(state: :approved), @app
      refute_includes @org.oauth_applications_requesting_approval(state: :denied), @app
    end

    test "does not create a pending approval for an app owned by the org" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@org_app, requestor: @owner)

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @org_app.id,
      ).first

      refute approval
    end

    test "requests approval for GitHub-owned apps" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@github_app, requestor: @owner)
      assert @org.approval_pending_for_oauth_application?(@github_app)
    end

    test "skips capable internal apps" do
      internal_app = create(:oauth_application)
      Apps::Privileged::Registry.configure(
        app_alias: :internal_app,
        app: internal_app,
        id: ->(*_) { internal_app.id },
        capabilities: {
          organization_oauth_app_policy_exempt: true
        }
      )
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(internal_app, requestor: @owner)
      refute @org.approval_pending_for_oauth_application?(internal_app)
    end

    test "skips GitHub desktop apps" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@github_desktop_app, requestor: @owner)
      refute @org.approval_pending_for_oauth_application?(@github_desktop_app)
    end

    test "does not create a pending approval if the org restricts outside collaborators" do
      @org.enable_oauth_application_restrictions
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)
      @org.disallow_third_party_access_requests_from_outside_collaborators(actor: @owner)

      @org.request_oauth_application_approval(@app, requestor: collaborator)

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first

      refute approval
    end
  end

  context "#approve_oauth_application" do
    test "marks the app's pending approval as 'approved'" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @rando)
      @org.approve_oauth_application(@app, approver: @owner)

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first

      assert approval
      assert_predicate approval, :approved?
      assert_includes @org.oauth_applications_requesting_approval, @app
      refute_includes @org.oauth_applications_requesting_approval(state: :pending), @app
      assert_includes @org.oauth_applications_requesting_approval(state: :approved), @app
      refute_includes @org.oauth_applications_requesting_approval(state: :denied), @app
    end

    test "creates an approval for a third-party app if no pending approval exists" do
      @org.enable_oauth_application_restrictions
      refute_includes @org.oauth_applications_requesting_approval(state: :pending), @app

      assert_difference "@org.reload.oauth_applications_requesting_approval(state: :approved).size" do
        @org.approve_oauth_application(@app, approver: @owner)
      end

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first!

      assert approval
      assert_predicate approval, :approved?
      assert_equal @owner, approval.requestor

      assert_includes @org.oauth_applications_requesting_approval(state: :approved), @app
    end

    test "emails all org members that have authorized the app" do
      @org.enable_oauth_application_restrictions
      refute_includes @org.oauth_applications_requesting_approval(state: :approved), @app

      assert_enqueued_with job: OrganizationApplicationAccessApprovedJob do
        @org.approve_oauth_application(@app, approver: @owner)
      end
    end

    test "does not create an approval for an app owned by the org" do
      @org.enable_oauth_application_restrictions

      assert_no_difference "@org.reload.oauth_applications_requesting_approval(state: :approved).size" do
        @org.approve_oauth_application(@org_app, approver: @owner)
      end
    end
  end

  context "#deny_oauth_application" do
    test "denies a pending approval" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)

      assert_difference "@org.reload.oauth_applications_requesting_approval(state: :denied).size" do
        @org.deny_oauth_application(@app, actor: @owner)
      end

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first
      assert approval
      assert_predicate approval, :denied?

      refute_includes @org.oauth_applications_requesting_approval(state: :pending), @app
      refute_includes @org.oauth_applications_requesting_approval(state: :approved), @app
      assert_includes @org.oauth_applications_requesting_approval(state: :denied), @app
    end

    test "denies existing approval" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@app, approver: @owner)

      assert_difference "@org.reload.oauth_applications_requesting_approval(state: :denied).size" do
        @org.deny_oauth_application(@app, actor: @owner)
      end

      approval = OauthApplicationApproval.where(
        organization_id: @org.id,
        application_id: @app.id,
      ).first
      assert approval
      assert_predicate approval, :denied?

      refute_includes @org.oauth_applications_requesting_approval(state: :pending), @app
      refute_includes @org.oauth_applications_requesting_approval(state: :approved), @app
      assert_includes @org.oauth_applications_requesting_approval(state: :denied), @app
    end

    test "deletes repo keys created by app in policymaker repos" do
      @org.allow_private_repository_forking(actor: @owner)
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@app, approver: @owner)

      assert_equal 0, PublicKey.count

      # Private repo - @org is policymaker
      priv_repo = create :private_repository, owner: @org
      create_sample_keys_in_repo(priv_repo)

      # Public repo - @org is policymaker
      pub_repo = create(:public_repository, owner: @org)
      create_sample_keys_in_repo(pub_repo)

      # Private fork - @org is policymaker
      priv_fork, status = priv_repo.fork(forker: @owner)
      assert_equal :created, status
      create_sample_keys_in_repo(priv_fork)

      # Public fork - @other_org is policymaker
      pub_fork, status = pub_repo.fork forker: @other_org.admins.first, org: @other_org
      assert_equal :created, status
      create_sample_keys_in_repo(pub_fork)

      [priv_repo, pub_repo, priv_fork, pub_fork].each do |repo|
        assert repo.public_keys.exists?(oauth_authorization_id: nil)
        assert repo.public_keys.exists?(oauth_authorization_id: @access.authorization.id)
        assert repo.public_keys.exists?(oauth_authorization_id: @other_access.authorization.id)
      end

      perform_enqueued_jobs(only: [RemoveRepoKeysForPolicymakerAndAppJob]) { @org.deny_oauth_application(@app, actor: @owner) }

      [priv_repo, pub_repo, priv_fork].each do |repo|
        assert repo.public_keys.exists?(oauth_authorization_id: nil)
        refute repo.public_keys.exists?(oauth_authorization_id: @access.authorization.id)
        assert repo.public_keys.exists?(oauth_authorization_id: @other_access.authorization.id)
      end

      assert pub_fork.public_keys.exists?(oauth_authorization_id: nil)
      assert pub_fork.public_keys.exists?(oauth_authorization_id: @access.authorization.id)
      assert pub_fork.public_keys.exists?(oauth_authorization_id: @other_access.authorization.id)
    end
  end

  context "allows_oauth_application?" do
    test "is not true by default for GitHub owned apps" do
      @org.enable_oauth_application_restrictions
      refute @org.allows_oauth_application?(@github_app)
    end

    test "is true for capable internal apps" do
      internal_app = create(:oauth_application)
      Apps::Privileged::Registry.configure(
        app_alias: :internal_app,
        app: internal_app,
        id: ->(*_) { internal_app.id },
        capabilities: {
          organization_oauth_app_policy_exempt: true
        }
      )

      @org.enable_oauth_application_restrictions
      assert @org.allows_oauth_application?(internal_app)
    end

    test "is true for GitHub Desktop apps" do
      @org.enable_oauth_application_restrictions
      assert @org.allows_oauth_application?(@github_desktop_app)
    end

    test "is true when the org does not have any app restrictions" do
      assert @org.allows_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is not approved" do
      @org.enable_oauth_application_restrictions
      refute @org.allows_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is pending approval" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      refute @org.allows_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is denied" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      @org.deny_oauth_application(@app, actor: @owner)
      refute @org.allows_oauth_application?(@app)
    end

    test "is true when the org restricts apps and the app is approved" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@app, approver: @owner)
      assert @org.allows_oauth_application?(@app)
    end

    test "is true when the org restricts apps and the app is org owned" do
      @org.enable_oauth_application_restrictions
      assert @org.allows_oauth_application?(@org_app)
    end

    test "is false when the org blocks the first-party app" do
      @org.stubs(:restricts_oauth_applications?).returns(true)
      @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      make_trusted_oauth_apps_owner
      gh_desktop_app = create :github_desktop_app
      gh_desktop_app.stubs(:github_owned?).returns(true)

      block = create(:oauth_application_approval, organization: @org, application: gh_desktop_app, state: :blocked)
      refute @org.allows_oauth_application?(gh_desktop_app)
    end

    test "emit DD stat when app is blocked and FF enabled" do
      @org.stubs(:restricts_oauth_applications?).returns(true)
      @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
      enable_feature_flag(:emit_dd_oap_violation_stat)

      make_trusted_oauth_apps_owner
      app = create :blockable_oauth_app
      create(:oauth_application_approval, organization: @org, application: app, state: :blocked)

      @org.allows_oauth_application?(app)

      assert_dogstats_increment 1, "org.check_allows_oauth_application", tags: ["result:blocked"]
    end

    test "emit DD stat when app is unapproved and FF enabled" do
      @org.stubs(:restricts_oauth_applications?).returns(true)
      @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(false)
      enable_feature_flag(:emit_dd_oap_violation_stat)

      app = create :oauth_application
      create(:oauth_application_approval, organization: @org, application: app, state: :denied)

      @org.allows_oauth_application?(app)

      assert_dogstats_increment 1, "org.check_allows_oauth_application", tags: ["result:unapproved"]
    end
  end

  context "approval_pending_for_oauth_application?" do
    test "is false when the org does not have any app restrictions" do
      refute @org.approval_pending_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app has no pending approval" do
      @org.enable_oauth_application_restrictions
      refute @org.approval_pending_for_oauth_application?(@app)
    end

    test "is true when the org restricts apps and the app is pending approval" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      assert @org.approval_pending_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is approved" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@app, approver: @owner)
      refute @org.approval_pending_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is denied" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      @org.deny_oauth_application(@app, actor: @owner)
      refute @org.approval_pending_for_oauth_application?(@app)
    end
  end

  context "approval_denied_for_oauth_application?" do
    test "is false when the org does not have any app restrictions" do
      refute @org.approval_denied_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app has no approval request" do
      @org.enable_oauth_application_restrictions
      refute @org.approval_pending_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is pending approval" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      refute @org.approval_denied_for_oauth_application?(@app)
    end

    test "is false when the org restricts apps and the app is approved" do
      @org.enable_oauth_application_restrictions
      @org.approve_oauth_application(@app, approver: @owner)
      refute @org.approval_denied_for_oauth_application?(@app)
    end

    test "is true when the org restricts apps and the app is denied" do
      @org.enable_oauth_application_restrictions
      @org.request_oauth_application_approval(@app, requestor: @owner)
      @org.deny_oauth_application(@app, actor: @owner)
      assert @org.approval_denied_for_oauth_application?(@app)
    end
  end

  context "#can_request_application_approval?" do
    test "when requests from outside collaborators not allowed, returns false" do
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)
      @org.disallow_third_party_access_requests_from_outside_collaborators(actor: @owner)

      refute @org.can_request_application_approval?(requestor: collaborator)
    end

    test "when requests from outside collaborators allowed, returns true" do
      org_repo = create(:repository, :minimal, owner: @org)
      collaborator = create(:user)
      org_repo.add_member(collaborator, action: :read)
      @org.allow_third_party_access_requests_from_outside_collaborators(actor: @owner)

      assert @org.can_request_application_approval?(requestor: collaborator)
    end

    test "when org member, returns true" do
      org_member = create(:user)
      @org.add_member(org_member)
      @org.disallow_third_party_access_requests_from_outside_collaborators(actor: @owner)

      assert @org.can_request_application_approval?(requestor: org_member)
    end
  end

  context "#first_party_oauth_app_restrictions_enabled?" do
    test "is false when OAP restrictions are disabled" do
      @org.stubs(:restricts_oauth_applications?).returns(false)
      refute @org.first_party_oauth_app_restrictions_enabled?
    end

    test "is false when first_party_oauth_app_controls_feature_enabled? is false" do
      @org.stubs(:first_party_oauth_app_controls_feature_enabled?).returns(false)
      refute @org.first_party_oauth_app_restrictions_enabled?
    end

    test "is true when OAP restrictions are enabled and first_party_oauth_app_controls_feature_enabled? is true" do
      @org.stubs(:restricts_oauth_applications?).returns(true)
      @org.stubs(:first_party_oauth_app_controls_feature_enabled?).returns(true)
      assert @org.first_party_oauth_app_restrictions_enabled?
    end
  end

  context "#first_party_oauth_app_controls_feature_enabled?" do
    test "is false when feature flag is disabled" do
      disable_feature_flag(:first_party_oauth_app_restrictions)
      refute @org.first_party_oauth_app_controls_feature_enabled?
    end

    test "is false when the org is not EMU enabled" do
      @org.stubs(:enterprise_managed_user_enabled?).returns(false)
      refute @org.first_party_oauth_app_controls_feature_enabled?
    end

    test "is true when FF is enabled for org, OAP is enabled and is EMU enabled" do
      disable_feature_flag(:first_party_oauth_app_restrictions) # Disable for all
      enable_feature_flag(:first_party_oauth_app_restrictions, @org)
      GitHub.stubs(:oauth_application_policies_enabled?).returns(true)
      @org.stubs(:enterprise_managed_user_enabled?).returns(true)
      assert @org.first_party_oauth_app_controls_feature_enabled?
    end

    test "is false when first_party_oauth_app_restrictions FF is enabled for business, OAP is enabled, is EMU enabled, and consider_business_oap_ff is disabled" do
      @org.business = create(:business)
      @org.save!

      disable_feature_flag(:first_party_oauth_app_restrictions) # Disable for all to start with a clean slate
      disable_feature_flag(:consider_business_oap_ff)
      enable_feature_flag(:first_party_oauth_app_restrictions, @org.business)
      GitHub.stubs(:oauth_application_policies_enabled?).returns(true)
      @org.stubs(:enterprise_managed_user_enabled?).returns(true)
      refute @org.first_party_oauth_app_controls_feature_enabled?
    end

    test "is true when first_party_oauth_app_restrictions FF is enabled for business, OAP is enabled, is EMU enabled, and consider_business_oap_ff is enabled" do
      @org.business = create(:business)
      @org.save!

      disable_feature_flag(:first_party_oauth_app_restrictions) # Disable for all to start with a clean slate
      enable_feature_flag(:consider_business_oap_ff)
      enable_feature_flag(:first_party_oauth_app_restrictions, @org.business)
      GitHub.stubs(:oauth_application_policies_enabled?).returns(true)
      @org.stubs(:enterprise_managed_user_enabled?).returns(true)
      assert @org.first_party_oauth_app_controls_feature_enabled?
    end
  end

  def create_sample_keys_in_repo(repo)
    # An hooman adds a key
    repo.public_keys.create! key: Sham.ssh_public_key

    repo.public_keys.create_with_verification \
      verifier: @access.user, key: Sham.ssh_public_key,
      oauth_authorization: @access.authorization

    repo.public_keys.create_with_verification \
      verifier: @other_access.user, key: Sham.ssh_public_key,
      oauth_authorization: @other_access.authorization
  end
end if GitHub.oauth_application_policies_enabled?

class OrganizationoauthAppPolicyMetByTest < GitHub::TestCase
  fixtures do
    @owner  = create :user, login: "owner"
    @rando  = create :user, login: "rando"

    @org = create :organization, admin: @owner

    @app     = make_oauth_app @rando
    @org_app = create :oauth_application, user: @org

    @github = create(:organization, login: "github")

    make_trusted_oauth_apps_owner
    @github_app = create :oauth_application, \
      user: GitHub.trusted_oauth_apps_owner
    @github_desktop_app = create :github_desktop_app
  end

  test "filters orgs based on OAuth app policy" do
    # No restrictions: All OAuth apps allowed
    assert_includes Organization.oauth_app_policy_met_by(@app), @org
    assert_includes Organization.oauth_app_policy_met_by(@org_app), @org

    # Restricting OAuth apps blocks third-party apps
    @org.enable_oauth_application_restrictions
    refute_includes Organization.oauth_app_policy_met_by(@app), @org
    assert_includes Organization.oauth_app_policy_met_by(@org_app), @org

    # Third-party apps are blocked while pending approval
    @org.request_oauth_application_approval(@app, requestor: @rando)
    refute_includes Organization.oauth_app_policy_met_by(@app), @org
    assert_includes Organization.oauth_app_policy_met_by(@org_app), @org

    # Approved third-party apps are allowed
    @org.approve_oauth_application(@app, approver: @owner)
    assert_includes Organization.oauth_app_policy_met_by(@app), @org

    # Allows capable internal and desktop GitHub apps
    refute_includes Organization.oauth_app_policy_met_by(@github_app), @org
    internal_app = create(:oauth_application)
    Apps::Privileged::Registry.configure(
      app_alias: :internal_app,
      app: internal_app,
      id: ->(*_) { internal_app.id },
      capabilities: {
        organization_oauth_app_policy_exempt: true
      }
    )

    assert_includes Organization.oauth_app_policy_met_by(internal_app), @org
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app), @org

    # Denied third-party apps are not allowed
    @org.deny_oauth_application(@app, actor: @owner)
    refute_includes Organization.oauth_app_policy_met_by(@app), @org
  end

  test "emits metric when ff enabled" do
    enable_feature_flag(:instrument_oap_met_by)
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    Organization.oauth_app_policy_met_by(@app)
    assert_equal 1, GitHub.dogstats.distributions("organizations.third_party_oap_met_by").count
  end

  test "filters out orgs that block client apps when FF enabled for org" do
    enable_feature_flag(:orgs_oap_met_by_first_party)

    foo_org = create(:organization, restrict_oauth_applications: true)
    foo_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
    enable_feature_flag(:first_party_oauth_app_restrictions, foo_org)

    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id
    # @org blocks app
    block = create(:oauth_application_approval, organization: foo_org, application: @github_desktop_app, state: :blocked)
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id

    disable_feature_flag(:first_party_oauth_app_restrictions, foo_org)
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id
  end

  test "correctly filters out orgs that block client apps when first_party_oauth_app_restrictions_enabled FF is disabled for an org" do
    enable_feature_flag(:orgs_oap_met_by_first_party)

    # Create a orgs
    foo_org = create(:organization, restrict_oauth_applications: true)
    bar_org = create(:organization, restrict_oauth_applications: true)
    foo_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
    bar_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

    enable_feature_flag(:first_party_oauth_app_restrictions, foo_org)
    enable_feature_flag(:first_party_oauth_app_restrictions, bar_org)

    # We haven't blocked an app yet, so this should be true
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), bar_org.id

    # orgs block app
    block = create(:oauth_application_approval, organization: foo_org, application: @github_desktop_app, state: :blocked)
    block = create(:oauth_application_approval, organization: bar_org, application: @github_desktop_app, state: :blocked)

    # # It should filter out the orgs since the org blocked the app
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), bar_org.id

    # The FF is disabled for one of the orgs, which should not filter out the org.
    disable_feature_flag(:first_party_oauth_app_restrictions, foo_org)
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), foo_org.id # This should fail once the bug is fixed. see: https://github.com/github/github/pull/282251
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), bar_org.id
  end

  test "filters out orgs that block client apps when first_party_oauth_app_restrictions_enabled FF enabled for business and consider_business_oap_ff FF is enabled" do
    # Consider businesses when checking for first_party_oauth_app_restrictions
    enable_feature_flag(:consider_business_oap_ff)

    enable_feature_flag(:orgs_oap_met_by_first_party)

    # Create a business-owned org
    business_org = create(:organization, business: create(:business), restrict_oauth_applications: true)
    business_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

    # Enable the FF for an org's business
    enable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)

    # We haven't blocked an app yet, so this should be true
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), business_org.id

    # org block app
    block = create(:oauth_application_approval, organization: business_org, application: @github_desktop_app, state: :blocked)

    # It should filter out the org since the org blocked the app
    refute_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), business_org.id

    # The FF is disabled for the org's business, so it should not filter out the org
    disable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), business_org.id
  end

  test "Does not filter out orgs that block client apps when first_party_oauth_app_restrictions_enabled FF enabled for business and consider_business_oap_ff FF is disabled" do
    # Do not consider businesses when checking for first_party_oauth_app_restrictions
    disable_feature_flag(:consider_business_oap_ff)

    enable_feature_flag(:orgs_oap_met_by_first_party)

    # Create a business-owned org
    business_org = create(:organization, business: create(:business), restrict_oauth_applications: true)

    business_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

    # Enable the FF for an org's business
    enable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)

    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), business_org.id

    # org block app
    block = create(:oauth_application_approval, organization: business_org, application: @github_desktop_app, state: :blocked)

    # It should not filter out the org since consider_business_oap_ff is disabled
    assert_includes Organization.oauth_app_policy_met_by(@github_desktop_app).map(&:id), business_org.id
  end

  test "returns unique orgs" do
    another_app = create :oauth_application
    @org.enable_oauth_application_restrictions
    @org.approve_oauth_application(@app, approver: @owner)
    @org.approve_oauth_application(another_app, approver: @owner)

    # Multiple approvals and an org-owned app provide multiple cases for the scope
    # conditions to be met, but we are only interested in the unique list.
    assert_same_elements [@org, @github], Organization.oauth_app_policy_met_by(@org_app)
  end
end if GitHub.oauth_application_policies_enabled?

class OrganizationoauthAppPolicyDeniesTest < GitHub::TestCase
  fixtures do
    @rando = create :user, login: "rando"
    @owner = create :user, login: "owner"
    @org   = create :organization, admin: @owner
    @app   = make_oauth_app @rando
  end

  test "filters orgs based on explicit denial of OAuth app" do
    @org.enable_oauth_application_restrictions
    refute_includes Organization.oauth_app_policy_denies(@app), @org

    @org.request_oauth_application_approval(@app, requestor: @owner)
    refute_includes Organization.oauth_app_policy_denies(@app), @org

    @org.deny_oauth_application(@app, actor: @owner)
    assert_includes Organization.oauth_app_policy_denies(@app), @org

    # Removing app restrictions removes the explicit denial
    @org.disable_oauth_application_restrictions
    refute_includes Organization.oauth_app_policy_denies(@app), @org
  end
end if GitHub.oauth_application_policies_enabled?

class OrganizationoauthAppPolicyBlocksTest < GitHub::TestCase
  fixtures do
    @owner = create :user, login: "owner"
    @org   = create :organization, admin: @owner
    make_trusted_oauth_apps_owner
    @app   = create :blockable_oauth_app
  end

  test "filters orgs based on explicit blocking of OAuth app when FF enabled for org" do
    @org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)
    @org.enable_oauth_application_restrictions
    enable_feature_flag(:first_party_oauth_app_restrictions, @org)

    refute_includes Organization.oauth_app_policy_blocks(@app), @org

    # Blocking the app blocks it
    @org.block_oauth_application(application: @app, actor: @owner)
    assert_includes Organization.oauth_app_policy_blocks(@app), @org

    # Disabling the FF ignores the explicit block
    disable_feature_flag(:first_party_oauth_app_restrictions, @org)
    refute_includes Organization.oauth_app_policy_blocks(@app), @org

    # Removing app restrictions ignores the explicit block
    @org.disable_oauth_application_restrictions
    refute_includes Organization.oauth_app_policy_blocks(@app), @org
  end

  test "does not filter orgs based on explicit blocking of OAuth app when first_party_oauth_app_restrictions FF enabled for business and consider_business_oap_ff FF is disabled" do
    # Do not consider businesses when checking for first_party_oauth_app_restrictions
    disable_feature_flag(:consider_business_oap_ff)

    # Create a business-owned org
    business_org = create(:organization, business: create(:business), restrict_oauth_applications: true)
    business_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

    # Enable FF org's business
    enable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)

    refute_includes Organization.oauth_app_policy_blocks(@app), business_org

    # Blocking the app blocks it
    business_org.block_oauth_application(application: @app, actor: @owner)

    # It should not filter out the org since consider_business_oap_ff is disabled
    refute_includes Organization.oauth_app_policy_blocks(@app), business_org
  end

  test "filters orgs based on explicit blocking of OAuth app when first_party_oauth_app_restrictions FF enabled for business and consider_business_oap_ff FF is enabled" do
    # Consider businesses when checking for first_party_oauth_app_restrictions
    enable_feature_flag(:consider_business_oap_ff)

    # Create a business-owned org
    business_org = create(:organization, business: create(:business), restrict_oauth_applications: true)
    business_org.stubs(:first_party_oauth_app_restrictions_enabled?).returns(true)

    # Enable FF org's business
    enable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)

    refute_includes Organization.oauth_app_policy_blocks(@app), business_org

    # Blocking the app blocks it
    business_org.block_oauth_application(application: @app, actor: @owner)
    assert_includes Organization.oauth_app_policy_blocks(@app), business_org

    # Disabling the FF ignores the explicit block
    disable_feature_flag(:first_party_oauth_app_restrictions, business_org.business)
    refute_includes Organization.oauth_app_policy_blocks(@app), business_org

    # Removing app restrictions ignores the explicit block
    business_org.disable_oauth_application_restrictions
    refute_includes Organization.oauth_app_policy_blocks(@app), business_org
  end
end if GitHub.oauth_application_policies_enabled?
