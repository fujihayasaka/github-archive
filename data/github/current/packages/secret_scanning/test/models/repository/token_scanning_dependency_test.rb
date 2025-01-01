# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/private_token_scanning_test_helper"

class RepositoryTokenScanningDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper
  include PrivateTokenScanningTestHelper
  include DependabotAlertsEnterpriseEnablementHelper
  include TurboghasHelpers
  include HydroTestHelpers

  fixtures do
    @business = create(:business)
    @admin = create(:user, login: "bizadmin")
    @org = create(:business_plus_org, admin: @admin, business: @business)
    @public_repo = create(:public_repository, owner: @org)
    @private_repo = create(:private_repository, owner: @org)
    @user_repo = create(:private_repository, owner: @admin)
    @user_private_repo = create(:private_repository, owner: @admin)
    @user_public_repo = create(:public_repository, owner: @admin)
    @non_admin_member = create(:user)
    @org.add_member(@non_admin_member, action: :read)
    @collaborator = create(:user)
    @private_repo.add_member(@collaborator)
    @security_manager_team = create(:security_manager_team, organization: @org)
    @security_manager = create(:user, login: "securitymanager")
    @security_manager_team.add_member(@security_manager)
    @private_repo.add_team(@security_manager_team, action: :read)
    @maintainer = create(:user, :verified, login: "maintainer", email: "maintainer@github.com")
    @private_repo.add_member(@maintainer, action: :maintain)

    @view_secret_scanning_alerts_user = create(:user, login: "viewsecretscanningalertsuser")
    @private_repo.add_member(@view_secret_scanning_alerts_user)
    grant_custom_role(user: @view_secret_scanning_alerts_user, target: @private_repo, fgps: [:view_secret_scanning_alerts])
    @resolve_secret_scanning_alerts_user = create(:user, login: "resolvesecretscanningalertsuser")
    @private_repo.add_member(@resolve_secret_scanning_alerts_user)
    grant_custom_role(user: @resolve_secret_scanning_alerts_user, target: @private_repo, fgps: [:resolve_secret_scanning_alerts])

    @view_secret_scanning_alerts_team = create(:team, organization: @org)
    @view_secret_scanning_alerts_team_member = create(:user, login: "viewsecretscanningalertsteammember")
    @view_secret_scanning_alerts_team.add_member(@view_secret_scanning_alerts_team_member)
    grant_custom_role(user: @view_secret_scanning_alerts_team, target: @private_repo, fgps: [:view_secret_scanning_alerts])

    @bypass_reviewer_org_fgp_user = create(:user)
    @org.add_member(@bypass_reviewer_org_fgp_user)
    grant_custom_org_role(user: @bypass_reviewer_org_fgp_user, target: @org, fgps: [:org_review_and_manage_secret_scanning_bypass_requests])


    assert @private_repo.readable_by?(@non_admin_member)
    assert @private_repo.readable_by?(@collaborator)
    assert @private_repo.readable_by?(@security_manager)

    @repo_with_commits = create(:repository, owner: @org, from_example: :with_tokens)

    GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::CHECK_BYPASS_REVIEWER_IN_REPO_REQUEST_LIST].enable(@public_repo)
  end

  setup do
    GitHub.stubs(:secret_scanning_email_settings_enabled?).returns(true)
    GitHub.newsies.get_and_update_settings(@admin) do |setting|
      setting.vulnerability_email = false # these lines can be removed once https://github.com/github/secret-scanning/issues/1915 ships
      setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
    end
    GitHub.newsies.get_and_update_settings(@security_manager) do |setting|
      setting.vulnerability_email = false
      setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
    end
    GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_user) do |setting|
      setting.vulnerability_email = false
      setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
    end
    GitHub.newsies.get_and_update_settings(@resolve_secret_scanning_alerts_user) do |setting|
      setting.vulnerability_email = false
      setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
    end
    GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_team_member) do |setting|
      setting.vulnerability_email = false
      setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
    end
    @business.mark_advanced_security_as_not_purchased_for_entity(actor: create(:user))
    GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(false)
  end

  context "push_protection_security_center_status" do
    test "returns enrolled when a repo with push protection enabled is not importing" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      SecurityProduct::VulnerabilityAlerts.stubs(enabled_for_instance?: false)
      @private_repo.enable_advanced_security!(actor: @admin)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
      token_scanning.enable(actor: @admin)
      push_protection = SecretScanning::Features::Repo::PushProtection.new(@private_repo)
      push_protection.enable(actor: @admin)

      status = @private_repo.push_protection_security_center_status

      assert_equal "enrolled", status.scanning_status
    end

    test "returns enrolled when a repo with push protection enabled is importing" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      SecurityProduct::VulnerabilityAlerts.stubs(enabled_for_instance?: false)
      @private_repo.enable_advanced_security!(actor: @admin)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
      token_scanning.enable(actor: @admin)
      push_protection = SecretScanning::Features::Repo::PushProtection.new(@private_repo)
      push_protection.enable(actor: @admin)
      @private_repo.stubs(:is_importing?).returns(true)

      status = @private_repo.push_protection_security_center_status

      assert_equal "enrolled", status.scanning_status
    end

    test "returns not_enrolled when a repo does not have push protection enabled" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      SecurityProduct::VulnerabilityAlerts.stubs(enabled_for_instance?: false)
      @private_repo.enable_advanced_security!(actor: @admin)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
      token_scanning.enable(actor: @admin)

      status = @private_repo.push_protection_security_center_status

      assert_equal "not_enrolled", status.scanning_status
    end

    test "returns not_enrolled when a repo that is importing does not have push protection enabled" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      SecurityProduct::VulnerabilityAlerts.stubs(enabled_for_instance?: false)
      @private_repo.enable_advanced_security!(actor: @admin)
      token_scanning = SecretScanning::Features::Repo::TokenScanning.new(@private_repo)
      token_scanning.enable(actor: @admin)
      @private_repo.stubs(:is_importing?).returns(true)

      status = @private_repo.push_protection_security_center_status

      assert_equal "not_enrolled", status.scanning_status
    end
  end

  context "find_commit" do
    test "returns commit if commit exists" do
      commit_oid = @repo_with_commits.default_oid
      refute_nil @repo_with_commits.find_commit(commit_oid)
    end

    test "returns nil if commit does not exist" do
      assert_nil @repo_with_commits.find_commit("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    end
  end

  context "find_wiki_commit" do
    test "returns commit if commit exists" do
      repo, wiki = create_repo_with_wiki
      wiki_commit_oid = wiki.default_oid

      refute_nil repo.find_wiki_commit(wiki_commit_oid)
    end

    test "returns nil if commit does not exist" do
      repo, wiki = create_repo_with_wiki

      assert_nil repo.find_wiki_commit("deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    end

    test "returns nil if wiki does not exist" do
      repo, wiki = create_repo_with_wiki
      repo_without_wiki = create(:repository, owner: @org, from_example: :with_tokens)

      # this wiki commit doesn't exist on repo_without_wiki
      wiki_commit_oid = wiki.default_oid

      assert_nil repo_without_wiki.find_wiki_commit(wiki_commit_oid)
    end
  end

  context "any_commits_authored_by_user?" do
    test "returns false if no commits authored by actor" do
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"]))
      repo.stubs(:find_wiki_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"]))
      refute repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns true if one repo commit authored by actor" do
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"])).then.returns(stub(author_email: @collaborator.stealth_email_string, author_emails: [@collaborator.stealth_email_string]))
      assert repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns true if one wiki commit authored by actor" do
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(nil)
      repo.stubs(:find_wiki_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"])).then.returns(stub(author_email: @collaborator.stealth_email_string, author_emails: [@collaborator.stealth_email_string]))
      assert repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns true if second commit oid is from wiki commit authored by actor" do
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"])).then.returns(nil)
      repo.stubs(:find_wiki_commit).returns(stub(author_email: @collaborator.stealth_email_string, author_emails: [@collaborator.stealth_email_string]))
      assert repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns true if second commit oid is from repo commit authored by actor" do
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(nil).then.returns(stub(author_email: @collaborator.stealth_email_string, author_emails: [@collaborator.stealth_email_string]))
      repo.stubs(:find_wiki_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"]))
      assert repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns false if commit is coauthored by actor without flags" do
      GitHub.flipper[:secret_scanning_co_author_alert_permissions].disable
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(nil).then.returns(stub(author_email: "not author email", author_emails: ["not author email", @collaborator.stealth_email_string]))
      repo.stubs(:find_wiki_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"]))
      refute repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end

    test "returns true if commit is coauthored by actor with flags" do
      GitHub.flipper[:secret_scanning_co_author_alert_permissions].enable
      repo = as_repo(@private_repo)
      repo.stubs(:find_commit).returns(nil).then.returns(stub(author_email: "not author email", author_emails: ["not author email", @collaborator.stealth_email_string]))
      repo.stubs(:find_wiki_commit).returns(stub(author_email: "not author email", author_emails: ["not author email"]))
      assert repo.any_commits_authored_by_user?(@collaborator, %w(123 123))
    end
  end

  context "token_scanning_users_to_notify" do
    test "returns authorized users that are watching the repo and have opted into email notifications for subscriptions" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      @private_repo.enable_advanced_security!(actor: @admin)
      SecretScanning::Features::Repo::TokenScanning.new(@private_repo).enable(actor: @admin)

      assert @admin.watch_repo(@private_repo)
      assert @security_manager.watch_repo(@private_repo)
      assert @view_secret_scanning_alerts_user.watch_repo(@private_repo)
      assert @resolve_secret_scanning_alerts_user.watch_repo(@private_repo)
      assert @view_secret_scanning_alerts_team_member.watch_repo(@private_repo)
      assert @maintainer.watch_repo(@private_repo)
      assert_empty @private_repo.token_scanning_users_to_notify

      GitHub.newsies.get_and_update_settings(@admin) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@security_manager) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_user) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@resolve_secret_scanning_alerts_user) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_team_member) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@maintainer) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      # resolve_secret_scanning_alerts_user shouldn't be allowed to view because they only have the resolve_ role, which doesn't allow viewing
      # maintainer shouldn't be allowed to view because it's not part of their role
      assert_same_elements [
        @admin,
        @security_manager,
        @view_secret_scanning_alerts_user,
        @view_secret_scanning_alerts_team_member
      ], @private_repo.token_scanning_users_to_notify
    end

    test "returns all authorized users when the secret_scanning_email_settings_enabled? config is disabled" do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      GitHub.stubs(:secret_scanning_email_settings_enabled?).returns(false)
      @private_repo.enable_advanced_security!(actor: @admin)
      SecretScanning::Features::Repo::TokenScanning.new(@private_repo).enable(actor: @admin)
      assert @admin.watch_repo(@private_repo)
      assert @security_manager.watch_repo(@private_repo)
      assert @view_secret_scanning_alerts_user.watch_repo(@private_repo)
      assert @resolve_secret_scanning_alerts_user.watch_repo(@private_repo)
      assert @view_secret_scanning_alerts_team_member.watch_repo(@private_repo)

      assert_same_elements [
        @admin,
        @security_manager,
        @view_secret_scanning_alerts_user,
        @resolve_secret_scanning_alerts_user,
        @view_secret_scanning_alerts_team_member
      ], @private_repo.token_scanning_users_to_notify
    end

    test "does not return users when token scanning is not enabled" do
      assert_empty @private_repo.token_scanning_users_to_notify

      GitHub.newsies.get_and_update_settings(@admin) do |setting|
        setting.vulnerability_email = true
      end

      GitHub.newsies.get_and_update_settings(@security_manager) do |setting|
        setting.vulnerability_email = true
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_user) do |setting|
        setting.vulnerability_email = true
      end

      GitHub.newsies.get_and_update_settings(@resolve_secret_scanning_alerts_user) do |setting|
        setting.vulnerability_email = true
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_team_member) do |setting|
        setting.vulnerability_email = true
      end

      assert_empty @private_repo.token_scanning_users_to_notify
    end

    test "returns authorized users that are subscribed to security alerts and have opted into email notifications for subscriptions", skip_enterprise: true do
      @business.mark_advanced_security_as_purchased_for_entity(actor: create(:user))
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      @private_repo.enable_advanced_security!(actor: @admin)
      SecretScanning::Features::Repo::TokenScanning.new(@private_repo).enable(actor: @admin)

      GitHub.newsies.get_and_update_settings(@admin) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@security_manager) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_user) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@resolve_secret_scanning_alerts_user) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@view_secret_scanning_alerts_team_member) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      GitHub.newsies.get_and_update_settings(@maintainer) do |setting|
        setting.subscribed_settings << Newsies::HANDLER_EMAIL
      end

      assert_same_elements [], T.must(Repository.find_by(id: @private_repo.id)).token_scanning_users_to_notify

      assert GitHub.newsies.subscribe_to_thread_types(@admin, @private_repo, [SecurityAlert]).value!

      assert GitHub.newsies.subscribe_to_thread_types(@security_manager, @private_repo, [SecurityAlert]).value!

      assert GitHub.newsies.subscribe_to_thread_types(@view_secret_scanning_alerts_user, @private_repo, [SecurityAlert]).value!

      assert GitHub.newsies.subscribe_to_thread_types(@resolve_secret_scanning_alerts_user, @private_repo, [SecurityAlert]).value!

      assert GitHub.newsies.subscribe_to_thread_types(@view_secret_scanning_alerts_team_member, @private_repo, [SecurityAlert]).value!

      assert GitHub.newsies.subscribe_to_thread_types(@maintainer, @private_repo, [SecurityAlert]).value!

      # resolve_secret_scanning_alerts_user should not get an email because having only the resolve_ role does not let you view
      # maintainer should not get an email because maintainers cannot view secret scanning alerts
      assert_same_elements [
        @admin,
        @security_manager,
        @view_secret_scanning_alerts_user,
        @view_secret_scanning_alerts_team_member,
      ], T.must(Repository.find_by(id: @private_repo.id)).token_scanning_users_to_notify
    end
  end

  context "token_scanning_service_unresolved_cache" do
    test "check that the default revision is 0" do
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      assert_equal 0, cache.revision
    end

    test "check that bump updates revision" do
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      cache.bump
      assert_equal 1, cache.revision
    end

    test "check that a get populates the data with negative when the service is down" do
      GitHub::TokenScanning::Service::Client
        .any_instance
        .stubs(:get_token_counts)
        .with do |arg|
          arg[:low_confidence]
        end
        .returns(TokenScanningCount.new(nil))
        .times 1
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      GitHub.cache.allow = /#{cache.cache_key(:low)}|#{cache.cache_key(:nonlow)}/

      assert_equal 0, cache.revision
      assert_equal -1, cache.count
      assert_nil GitHub.cache.get(cache.cache_key(:low))
      assert_nil GitHub.cache.get(cache.cache_key(:nonlow))
    end

    test "getting count returns -1 when getting nonlow conf count fails" do
      GitHub::TokenScanning::Service::Client
        .any_instance
        .stubs(:get_token_counts)
        .with do |arg|
          arg[:low_confidence]
        end
        .returns(TokenScanningCount.new(2))
        .times 1
      GitHub::TokenScanning::Service::Client
        .any_instance
        .stubs(:get_token_counts)
        .with do |arg|
          arg[:low_confidence].nil?
        end
        .returns(TokenScanningCount.new(nil))
        .times 1
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      GitHub.cache.allow = /#{cache.cache_key(:low)}|#{cache.cache_key(:nonlow)}/

      assert_equal 0, cache.revision
      assert_equal -1, cache.count
      assert_equal 2, GitHub.cache.get(cache.cache_key(:low))
      assert_nil GitHub.cache.get(cache.cache_key(:nonlow))

      GitHub.cache.delete(cache.cache_key(:nonlow))
      GitHub.cache.delete(cache.cache_key(:low))
    end

    test "check that a get populates the data in cache with count when the service is up" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(2))
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      GitHub.cache.allow = /#{cache.cache_key(:nonlow)}|#{cache.cache_key(:low)}/

      assert_equal 0, cache.revision
      assert_nil GitHub.cache.get(cache.cache_key(:nonlow))
      assert_nil GitHub.cache.get(cache.cache_key(:low))
      assert_equal 4, cache.count
      refute_nil GitHub.cache.get(cache.cache_key(:nonlow))
      refute_nil GitHub.cache.get(cache.cache_key(:low))

      GitHub.cache.delete(cache.cache_key(:nonlow))
      GitHub.cache.delete(cache.cache_key(:low))
    end

    test "check that a bump gets the updated count" do
      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(2))
      cache = Repository::TokenScanningDependency::TokenScanningServiceUnresolvedCache.new(@private_repo.id, @admin)
      GitHub.cache.allow = /#{cache.cache_key(:low)}|#{cache.cache_key(:nonlow)}/

      assert_equal 0, cache.revision
      assert_nil GitHub.cache.get(cache.cache_key(:nonlow))
      assert_nil GitHub.cache.get(cache.cache_key(:low))
      assert_equal 4, cache.count
      refute_nil GitHub.cache.get(cache.cache_key(:nonlow))
      refute_nil GitHub.cache.get(cache.cache_key(:low))

      GitHub.cache.delete(cache.cache_key(:nonlow))
      GitHub.cache.delete(cache.cache_key(:low))

      GitHub::TokenScanning::Service::Client.any_instance.stubs(:get_token_counts).returns(TokenScanningCount.new(3))

      cache.bump
      GitHub.cache.allow = /#{cache.cache_key(:low)}|#{cache.cache_key(:nonlow)}/

      assert_equal 1, cache.revision
      assert_nil GitHub.cache.get(cache.cache_key(:nonlow))
      assert_nil GitHub.cache.get(cache.cache_key(:low))
      assert_equal 6, cache.count
      refute_nil GitHub.cache.get(cache.cache_key(:nonlow))
      refute_nil GitHub.cache.get(cache.cache_key(:low))

      GitHub.cache.delete(cache.cache_key(:nonlow))
      GitHub.cache.delete(cache.cache_key(:low))
    end
  end

  context "ensure_backfill_scan_if_enabled" do
    test "queues a backfill scan for private repos" do
      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      end
      @private_repo.enable_advanced_security!(actor: @admin)
      SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@admin, services_to_enable: [:token_scanning])
      @private_repo.reload

      refute_nil @private_repo.token_scan_status
      assert_equal "performed_by_token_scanning_service", @private_repo.token_scan_status.scan_state

      assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
      assert_hydro_published_partial({
        full_scan_type: {},
        type: :START,
        wiki_scanning: false,
      }, schema: "token_scanning_service.v0.BackfillRequest")
    end

    test "queues a backfill scan for private repos if a pre-existing entry marked it non-qualifying" do
      token_scan_status = create(:token_scan_status, repository: @private_repo, scan_state: :non_qualifying_repo)

      if GitHub.enterprise?
        GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
      else
        @business.mark_advanced_security_as_purchased_for_entity(actor: @admin)
      end
      @private_repo.enable_advanced_security!(actor: @admin)
      SecurityProduct::ServiceManager.new(@private_repo).toggle_services(@admin, services_to_enable: [:token_scanning])
      @private_repo.reload

      refute_nil @private_repo.token_scan_status
      assert_equal "performed_by_token_scanning_service", @private_repo.token_scan_status.scan_state

      assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
      assert_hydro_published_partial({
        full_scan_type: {},
        type: :START,
        wiki_scanning: false,
      }, schema: "token_scanning_service.v0.BackfillRequest")
    end

    test "fires dogstats for backfill repo status ensure failed scenario" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      TokenScanStatus.expects(:ensure_status_entry_for_repo!).raises(ActiveRecord::RecordInvalid)
      Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
      @private_repo.enable_advanced_security!(actor: @admin)
      SecretScanning::Features::Repo::TokenScanning.new(@private_repo).enable(actor: @admin)

      @private_repo.ensure_backfill_scan_status
      @private_repo.ensure_backfill_scan_if_enabled(actor: @admin)
      @private_repo.reload

      assert_nil @private_repo.token_scan_status
      assert_equal 1, GitHub.dogstats.increments("secret_scanning.backfill_status_ensure_failure").length

      assert_hydro_messages(count: 1, schema: "token_scanning_service.v0.BackfillRequest")
      assert_hydro_published_partial({
        full_scan_type: {},
        type: :START,
        wiki_scanning: false,
      }, schema: "token_scanning_service.v0.BackfillRequest")
    end
  end

  context "has_org_delegated_bypass_fgp?" do
    test "returns false if repo is not owned by an org" do
      refute @user_public_repo.has_org_delegated_bypass_fgp?(@admin)
    end

    test "returns true if the actor has the org FGP" do
      assert @public_repo.has_org_delegated_bypass_fgp?(@bypass_reviewer_org_fgp_user)
    end

    test "returns false" do
      refute @public_repo.has_org_delegated_bypass_fgp?(@view_secret_scanning_alerts_user)
    end
  end

  context "can_view_delegated_bypass_requests_list?" do
    test "returns false if owner is not an org" do
      refute @user_public_repo.can_view_delegated_bypass_requests_list?(@admin)
    end

    test "returns true for org admins" do
      assert @public_repo.owner.adminable_by?(@admin)
      assert @public_repo.can_view_delegated_bypass_requests_list?(@admin)
    end

    test "returns true for security managers" do
      assert @public_repo.can_view_delegated_bypass_requests_list?(@security_manager)
    end

    test "returns true for bypass reviewer users" do
      SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@public_repo, @collaborator).returns(true)
      assert @public_repo.can_view_delegated_bypass_requests_list?(@collaborator)
    end

    test "returns false for bypass reviewer users when FF is disabled" do
      GitHub.flipper[SecretScanning::Features::FeatureFlagHelper::FeatureFlags::CHECK_BYPASS_REVIEWER_IN_REPO_REQUEST_LIST].disable
      SecretScanning::Services::DelegatedBypassService.stubs(:can_review_bypass_request?).with(@public_repo, @collaborator).returns(true)
      refute @public_repo.can_view_delegated_bypass_requests_list?(@collaborator)
    end

    test "returns true for users with the org FGP" do
      # We want to test users who are granted the org FGP via custom roles, not admins + security managers
      # who inherit it by default.
      refute @public_repo.owner.adminable_by?(@bypass_reviewer_org_fgp_user)
      assert @public_repo.can_view_delegated_bypass_requests_list?(@bypass_reviewer_org_fgp_user)
    end

    test "returns false" do
      refute @public_repo.can_view_delegated_bypass_requests_list?(@view_secret_scanning_alerts_user)
    end
  end

  private

  sig { params(repo: Repository).returns(Repository) }
  def as_repo(repo)
    repo
  end

  def create_repo_with_wiki
    repo = create(:repository, owner: @admin, from_example: :with_tokens)
    repo.initialize_wiki(repo.owner)

    wiki = repo.unsullied_wiki
    wiki.pages.create "setup wiki", :markdown, "wiki setup contents", "setting up wiki", @admin

    [repo, wiki]
  end
end
