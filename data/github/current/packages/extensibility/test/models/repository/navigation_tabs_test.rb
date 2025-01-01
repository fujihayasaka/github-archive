# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryNavigationTabsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  class NavigationTabsProviderComponent < Repositories::UnderlineNavComponent
    include Repository::NavigationTabs

    attr_reader :current_repository, :current_user, :user_can_write_wiki

    def initialize(repository:, current_user:, user_can_write_wiki: nil)
      @current_repository = repository
      @current_user = current_user
      @user_can_write_wiki = user_can_write_wiki
    end

    def current_branch_or_tag_name_for_urls; end

    def logged_in?
      !!current_user
    end

    def default_url_options
      { host: GitHub.host_name }
    end

    def controller; end
  end

  fixtures do
    @user = create(:user)
    @repository = create(:repository)
    @repository.tabs.create(url: "https://example.com", anchor: "Custom Tab")
    @repository.tabs.create(url: "https://example.com", anchor: "Custom Tab 2")
    @owned_repo = create(:repository, owner: @user)
    @private_repo = create(:private_repository)

    @org = create(:business_plus_organization, admin: @user)
    @silver_org = create(:organization)
    @org_repository = create(:repository, owner: @org)
    @org_private_repository = create(:private_repository, owner: @org)
    @silver_org_repository = create(:repository, owner: @silver_org)
    @silver_org_private_repository = create(:private_repository, owner: @silver_org)
    @collaborator = create(:user)
    @maintain_user = create(:user)
    @org_repository.add_member(@maintain_user)

    @moderator = create(:user)
    @org.add_member(@moderator)
    @org.moderation.add_moderator(@moderator, actor: @org.admin)
    @silver_org.add_member(@moderator)
    @silver_org.moderation.add_moderator(@moderator, actor: @silver_org.admin)

    @memex = create(:memex_project, owner: @org)
    @memex2 = create(:memex_project, owner: @org)

  end

  setup do
    disable_feature_flag(ProjectsClassicSunset::SUNSET_OVERRIDE_FLAG)
    disable_feature_flag(:github_models_repo_tab)
    disable_feature_flag(:navbar_hits)
    disable_feature_flag(:navbar_hits_details)
    disable_feature_flag(:navbar_counter_caching)
  end

  def navbar_metrics(counter_name)
    [
      "github.nav_bar.#{counter_name}_count.time",
      "github.nav_bar.#{counter_name}_count.cpu_time",
      "github.nav_bar.#{counter_name}_count.cpu_thread_time",
      "github.nav_bar.#{counter_name}_count.idle_time",
      "github.nav_bar.#{counter_name}_count.mysql_queries",
      "github.nav_bar.#{counter_name}_count.mysql_time",
      "github.nav_bar.#{counter_name}_count.memcached_queries",
      "github.nav_bar.#{counter_name}_count.memcached_time",
      "github.nav_bar.#{counter_name}_count.redis_queries",
      "github.nav_bar.#{counter_name}_count.redis_time",
    ]
  end

  context "#links" do
    test "it can provide all tabs, including custom tabs" do
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.stubs(:show_issues?).returns(true)
      provider.stubs(:show_discussions?).returns(true)
      provider.stubs(:show_actions?).returns(true)
      provider.stubs(:show_projects?).returns(true)
      provider.stubs(:show_wiki?).returns(true)
      provider.stubs(:show_insights?).returns(true)
      provider.stubs(:show_config?).returns(true)
      GitHub.stubs(:custom_tabs_enabled?).returns(true)

      tabs = provider.links
      assert_equal tabs.map { |tab| tab.text }, ["Code", "Issues", "Pull requests", "Discussions", "Actions", "Projects", "Wiki", "Security", "Insights", "Settings", "Custom Tab", "Custom Tab 2"]

      settings_tab = tabs.find { |tab| tab.text == "Settings" }
      assert_equal settings_tab.href, "/#{@repository.nwo}/settings"
      security_tab = tabs.find { |tab| tab.text == "Security" }
      assert_nil security_tab.count
    end

    test "code, pull request, and security tabs are always provided" do
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.stubs(:show_issues?).returns(false)
      provider.stubs(:show_discussions?).returns(false)
      provider.stubs(:show_actions?).returns(false)
      provider.stubs(:show_projects?).returns(false)
      provider.stubs(:show_wiki?).returns(false)
      provider.stubs(:show_insights?).returns(false)
      provider.stubs(:show_models?).returns(false)
      provider.stubs(:show_config?).returns(false)
      GitHub.stubs(:custom_tabs_enabled?).returns(false)

      tabs = provider.links
      assert_equal tabs.map { |tab| tab.text }, ["Code", "Pull requests", "Security"]
    end

    if GitHub.repository_advisories_enabled?
      test "security tab isn't provided for advisory workspaces" do
        disable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions)

        advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)
        provider = NavigationTabsProviderComponent.new(repository: advisory.workspace_repository, current_user: @user)

        assert_nil provider.links.find { |tab| tab.text == "Security" }
      end
    end

    context "Settings tab" do
      test "it provides a security analysis tab when not showing config but the user can manage security settings for the org repository" do
        provider = NavigationTabsProviderComponent.new(repository: @org_repository, current_user: @user)
        provider.stubs(:show_config?).returns(false)
        provider.stubs(:can_manage_code_security_settings?).returns(true)

        tabs = provider.links
        settings_tab = tabs.find { |tab| tab.text == "Settings" }
        assert_equal settings_tab.href, "/#{@org_repository.nwo}/settings/security_analysis"
      end
    end

    test "a counter can be provided for the Security tab" do
      tabs = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user).links(security_counter: 2)

      security_tab = tabs.find { |tab| tab.text == "Security" }
      assert_equal security_tab.count, 2
    end
  end

  context "#show_actions?" do
    test "it returns true if GitHub Actions is disabled but setup is pending" do
      GitHub.actions_enabled = false
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.show_actions?
    end

    test "it returns false if GitHub Actions is disabled and setup is not pending" do
      GitHub.actions_enabled = false
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(false)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      refute provider.show_actions?
    end

    test "it returns false if GitHub Actions is enabled but disabled for the repo and setup is pending" do
      GitHub.actions_enabled = true
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)

      @repository.disable_actions(actor: @user)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      refute provider.show_actions?
    end

    test "it returns true if GitHub Actions is enabled and enabled for the repo and setup is pending" do
      GitHub.actions_enabled = true
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)

      @repository.enable_actions(actor: @user)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.show_actions?
    end

    test "it returns false if the repositories_actions_checks database is not loading" do
      GitHub.actions_enabled = true
      GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)

      @repository.disable_actions(actor: @user)

      [ActiveRecord::StatementInvalid, ActiveRecord::ConnectionFailed].each do |error_class|
        Repository.any_instance.stubs(:workflows).raises(error_class.new, "RAC is down!").once

        provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
        refute provider.show_actions?
      end
    end

    if GitHub.repository_advisories_enabled?
      test "it returns false for advisory workspaces that don't have actions enabled" do
        GitHub.actions_enabled = true
        GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)
        enable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions, @org_repository)
        @org_repository.stubs(:actions_enabled?).returns(false)

        advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)
        provider = NavigationTabsProviderComponent.new(repository: advisory.workspace_repository, current_user: @user)

        refute provider.show_actions?
      end

      test "it returns true for advisory workspaces that have actions enabled" do
        GitHub.actions_enabled = true
        GitHub.stubs(:actions_packages_enterprise_setup_pending?).returns(true)
        enable_feature_flag(:maintainer_love_advisory_workspaces_can_use_actions, @org_repository)
        @org_repository.stubs(:actions_enabled?).returns(true)

        advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)
        provider = NavigationTabsProviderComponent.new(repository: advisory.workspace_repository, current_user: @user)

        assert provider.show_actions?
      end
    end
  end

  context "#show_config?" do
    test "returns true when the user is enabled for authzd and has necessary permission" do
      Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
      Repository.any_instance.stubs(:async_show_config_for?).returns(true)
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)
      assert provider.show_config?
    end

    test "returns true for admin" do
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @org_repository)
      assert provider.show_config?
    end

    test "returns false where there is no user" do
      provider = NavigationTabsProviderComponent.new(current_user: nil, repository: @repository)
      refute provider.show_config?
    end

    test "returns false for triage" do
      user = create(:user)
      @org_repository.add_member(user, action: :triage)
      provider = NavigationTabsProviderComponent.new(current_user: user, repository: @org_repository)
      refute provider.show_config?
    end

    test "returns true for maintainer" do
      user = create(:user)
      @org_repository.add_member(user, action: :maintain)
      provider = NavigationTabsProviderComponent.new(current_user: user, repository: @org_repository)
      assert provider.show_config?
    end

    if GitHub.organization_moderators_enabled?
      test "returns true for org moderator for org that supports FGPs" do
        assert_predicate @org, :custom_roles_supported?
        refute @org.adminable_by?(@moderator)
        assert @org.moderator?(@moderator)
        provider = NavigationTabsProviderComponent.new(
          current_user: @moderator,
          repository: @org_repository,
        )
        assert_predicate provider, :show_config?
      end

      test "returns false for org moderator on private repo for org that supports FGPs" do
        assert_predicate @org, :custom_roles_supported?
        refute @org.adminable_by?(@moderator)
        assert @org.moderator?(@moderator)
        provider = NavigationTabsProviderComponent.new(
          current_user: @moderator,
          repository: @org_private_repository,
        )
        refute_predicate provider, :show_config?
      end

      test "returns true for org moderator for org that does not support FGPs" do
        refute_predicate @silver_org, :custom_roles_supported?
        refute @silver_org.adminable_by?(@moderator)
        assert @silver_org.moderator?(@moderator)
        provider = NavigationTabsProviderComponent.new(
          current_user: @moderator,
          repository: @silver_org_repository,
        )
        assert_predicate provider, :show_config?
      end

      test "returns false for org moderator on private repo for org that does not support FGPs" do
        refute_predicate @silver_org, :custom_roles_supported?
        refute @silver_org.adminable_by?(@moderator)
        assert @silver_org.moderator?(@moderator)
        provider = NavigationTabsProviderComponent.new(
          current_user: @moderator,
          repository: @silver_org_private_repository,
        )
        refute_predicate provider, :show_config?
      end
    end

    test "returns false for write access only collab" do
      provider = NavigationTabsProviderComponent.new(current_user: @collab, repository: @org_repository)
      refute provider.show_config?
    end

    test "returns false for random user" do
      provider = NavigationTabsProviderComponent.new(current_user: create(:user), repository: @org_repository)
      refute provider.show_config?
    end

    test "returns false for advisory workspaces" do
      advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: advisory.workspace_repository)
      refute provider.show_config?
    end

    context "FGP with authzd" do
      test "returns false for user with Custom Role without relevant FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        custom_roles_user = create(:user)
        custom_role = create_custom_role(role_name: "foobar", owner: @org, fgps: [:push_protected_branch, :edit_repo_metadata])

        # grant user custom role
        @org_repository.send(:grant, custom_roles_user, custom_role.name)

        provider = NavigationTabsProviderComponent.new(current_user: custom_roles_user, repository: @org_repository)
        refute provider.show_config?
      end

      test "returns true for Custom Role user with manage_settings_wiki FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:manage_settings_wiki])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      test "returns true for Custom Role user with manage_settings_projects FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:manage_settings_projects])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      test "returns true for Custom Role user with manage_settings_merge_types FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:manage_settings_merge_types])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      test "returns true for Custom Role user with manage_settings_pages FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:manage_settings_pages])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      test "returns true for Custom Role user with set_interaction_limits FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:set_interaction_limits])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      test "returns true for Custom Role user with manage_webhooks FGP" do
        Repository.any_instance.stubs(:show_config_authzd_enabled?).returns(true)
        grant_custom_role(user: @collaborator, target: @org_repository, fgps: [:manage_webhooks])
        provider = NavigationTabsProviderComponent.new(current_user: @collaborator, repository: @org_repository)
        assert provider.show_config?
      end

      if GitHub.interaction_limits_enabled?
        test "returns true for org moderator" do

          moderator = create(:user)
          @org.add_member(moderator)
          @org.moderation.add_moderator(moderator, actor: @org.admin)
          refute @org.adminable_by?(moderator)
          assert @org.moderator?(moderator)
          provider = NavigationTabsProviderComponent.new(current_user: moderator, repository: @org_repository)
          assert provider.show_config?
        end
      end
    end
  end

  context "#show_discussions?" do
    test "false if the repository has discussions turned off" do
      @repository.turn_off_discussions(actor: @user, instrument: false)

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

      refute provider.show_discussions?
    end

    test "true if the repository has discussions turned on" do
      @repository.turn_on_discussions(actor: @user, instrument: false)

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

      assert provider.show_discussions?
    end

    test "true for private repository with discussions turned on" do
      @private_repo.turn_on_discussions(actor: @user, instrument: false)

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @private_repo)

      assert provider.show_discussions?
    end

    test "true if the repository has never had discussions turned on and the viewer should see the unboxing tab" do
      create_list(:issue, 5, repository: @owned_repo)
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @owned_repo)

      assert provider.show_discussions?
    end

    test "false if the repository has never had discussions turned on and the viewer should not see the unboxing tab" do
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

      refute provider.show_discussions?
    end

    test "false if the repository has never had discussions turned on and the viewer is anonymous" do
      provider = NavigationTabsProviderComponent.new(current_user: nil, repository: @repository)

      refute provider.show_discussions?
    end

    test "false if the viewer has dismissed the unboxing tab" do
      @maintain_user.dismiss_repository_notice("discussions_tab", repository_id: @org_repository.id)
      provider = NavigationTabsProviderComponent.new(current_user: @maintain_user, repository: @org_repository)

      refute provider.show_discussions?
    end

    test "false if the repository has explicitly turned discussions off" do
      @owned_repo.turn_on_discussions(actor: @user, instrument: false)
      @owned_repo.turn_off_discussions(actor: @user, instrument: false)

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @owned_repo)

      refute provider.show_discussions?
    end

    test "false if the repository would normally show unboxing tab but discussions not available in environment" do
      GitHub.stubs(:discussions_available_on_platform?).returns(false)

      create_list(:issue, 5, repository: @owned_repo)
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @owned_repo)

      refute provider.show_discussions?
    end
  end

  context "#show_models?" do
    if GitHub.models_enabled?
      test "true if the Models feature flag is enabled" do
        enable_feature_flag(:github_models_repo_tab)

        provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

        assert provider.show_models?
      end

      test "false if the Models feature flag is enabled" do
        disable_feature_flag(:github_models_repo_tab)

        provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

        refute provider.show_models?
      end
    end

    unless GitHub.models_enabled?
      test "false even if the Models feature flag is enabled" do
        enable_feature_flag(:github_models_repo_tab)

        provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @repository)

        refute provider.show_models?
      end
    end
  end

  context "#show_insights?" do
    if GitHub.repository_advisories_enabled?
      test "it returns true when repo is not an advisory workspace" do
        provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

        assert provider.show_insights?
      end

      test "it returns false when repo is an advisory workspace" do
        advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)
        provider = NavigationTabsProviderComponent.new(repository: advisory.workspace_repository, current_user: @user)

        refute provider.show_insights?
      end
    end

    test "it returns false if dependency graph is disabled and plan does not support insights" do
      @repository.stubs(:plan_supports?).returns(false)
      GitHub.stubs(:dependency_graph_enabled?).returns(false)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      refute provider.show_insights?
    end
  end

  context "#show_issues?" do
    test "it returns true if the repository has issues" do
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.show_issues?
    end

    test "it returns false if the repository does not have issues" do
      provider = NavigationTabsProviderComponent.new(repository: create(:repository, has_issues: false), current_user: @user)

      refute provider.show_issues?
    end
  end

  context "#show_projects?" do
    test "it returns true if the repository has memex projects enabled" do
      @repository.disable_repository_projects(actor: @user)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.show_projects?
    end

    test "it returns false if the repository does not have memex projects enabled" do
      @repository.disable_repository_memex_projects(actor: @user)
      @repository.disable_repository_projects(actor: @user)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      refute provider.show_projects?
    end

    test "it returns false if the org projects disabled" do
      @org_repository.disable_repository_projects(actor: @user)
      @org.disable_organization_projects(actor: @user)

      provider = NavigationTabsProviderComponent.new(repository: @org_repository, current_user: @user)

      refute provider.show_projects?
    end

    if GitHub.repository_advisories_enabled?
      test "it returns false for advisory workspaces" do
        advisory = create(:repository_advisory, :with_workspace, repository: @org_repository)
        provider = NavigationTabsProviderComponent.new(repository: advisory.workspace_repository, current_user: @user)

        refute provider.show_projects?
      end
    end
  end

  context "#show_wiki?" do
    test "it returns true if the user can view wikis" do
      @repository.stubs(:show_wiki?).with(@user, user_can_write_wiki: nil).returns(true)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.show_wiki?
    end

    test "it returns false if the user cannot view wikis" do
      @repository.stubs(:show_wiki?).with(@user, user_can_write_wiki: nil).returns(false)
      provider = NavigationTabsProviderComponent.new(repository: @private_repo, current_user: @user)

      refute provider.show_wiki?
    end

    test "it does not error on spokes client error" do
      @repository.stubs(:show_wiki?).raises(GitHub::Spokes::ClientError.new("Spokes is down!"))
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      refute provider.show_wiki?
    end
  end

  context "#open_issue_count" do
    test "it returns the repository issue count for the user" do
      @repository.stubs(:open_issue_count_for).with(@user).returns(7)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      assert_equal provider.open_issue_count, 7
    end

    test "it emits dogstatsd metrics for mysql calls if ff enabled " do
      enable_feature_flag(:navbar_hits)
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_issue_count, 1
      navbar_metrics("issue").each do |metric_name|
        assert_equal 1, GitHub.dogstats.distributions(metric_name, tags: expected_tags).length
      end
    end

    test "it emits dogstatsd metric with detailed tags if ff enabled" do
      enable_feature_flag(:navbar_hits)
      enable_feature_flag(:navbar_hits_details)
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_issue_count, 1
      navbar_metrics("issue").each do |metric_name|
        metrics = GitHub.dogstats.distributions(metric_name, tags: expected_tags)
        assert_equal 1, metrics.length
        assert metrics.first.tags.include?("repo_id:#{@repository.id}")
      end
    end

    test "it does not emit dogstatsd metric with detailed tags if ff disabled" do
      enable_feature_flag(:navbar_hits)
      disable_feature_flag(:navbar_hits_details)
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_issue_count, 1
      navbar_metrics("issue").each do |metric_name|
        metrics = GitHub.dogstats.distributions(metric_name, tags: expected_tags)
        assert_equal 1, metrics.length
        assert metrics.first.tags.none? { |tag| tag.start_with?("repo_id:") }
      end
    end

    test "it does not emits dogstatsd metric for mysql calls if ff disabled" do
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert_equal provider.open_issue_count, 1
      navbar_metrics("issue").each do |metric_name|
        assert_equal 0, GitHub.dogstats.distributions(metric_name).length
      end
    end

    test "it does not use caching if any required feature flag is disabled" do
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      @user.stubs(:feature_enabled?).with(:magic_shell_caching).returns(false)

      GitHub.cache.expects(:get).never
      GitHub.cache.expects(:set).never

      # navbar_hits disabled
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(false)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(true)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(true)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1

      # navbar_hits_details disabled
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(true)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(false)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(true)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1

      # navbar_counter_caching disabled
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(true)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(true)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(false)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1
    end

    test "it does not use caching for unsupported viewer/repo cases" do
      @repository.stubs(:open_issue_count_for).with(@user).returns(1)
      @user.stubs(:feature_enabled?).with(:magic_shell_caching).returns(false)

      GitHub.cache.expects(:get).never
      GitHub.cache.expects(:set).never

      # enable all flags
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(true)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(true)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(true)

      # viewer is site_admin case
      @user.stubs(:site_admin?).returns(true)
      @user.stubs(:spammy?).returns(false)
      @repository.stubs(:spammy?).returns(false)
      @repository.stubs(:owner_id).returns(@user.id + 1)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1

      # viewer is spammy case
      @user.stubs(:site_admin?).returns(false)
      @user.stubs(:spammy?).returns(true)
      @repository.stubs(:spammy?).returns(false)
      @repository.stubs(:owner_id).returns(@user.id + 1)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1

      # repo is spammy case
      @user.stubs(:site_admin?).returns(false)
      @user.stubs(:spammy?).returns(false)
      @repository.stubs(:spammy?).returns(true)
      @repository.stubs(:owner_id).returns(@user.id + 1)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1

      # viewer is owner case
      @user.stubs(:site_admin?).returns(false)
      @user.stubs(:spammy?).returns(false)
      @repository.stubs(:spammy?).returns(false)
      @repository.stubs(:owner_id).returns(@user.id)

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      provider.expects(:counter_cache_key).never
      assert_equal provider.open_issue_count, 1
    end

    test "it uses caching if the feature flags are enabled and it's a supported viewer/repo case -- cache miss" do
      @user.stubs(:feature_enabled?).with(:magic_shell_caching).returns(false)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      # enable all flags
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(true)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(true)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(true)

      # viewer is regular, non-spammy user case
      @user.stubs(:site_admin?).returns(false)
      @user.stubs(:spammy?).returns(false)
      @repository.stubs(:spammy?).returns(false)
      @repository.stubs(:owner_id).returns(@user.id + 1)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      provider.expects(:counter_cache_key).once.returns("navbar_cache-repo-test")
      GitHub.cache.expects(:get).with("navbar_cache-repo-test").once
      @repository.expects(:open_issue_count_for).with(@user, limit: 5100).once.returns(13)
      provider.expects(:counter_caching_ttl).once.returns(5)
      GitHub.cache.expects(:set).with("navbar_cache-repo-test", 13, 5).once

      assert_equal provider.open_issue_count, 13

      expected_tags = [
        "logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false",
        "navbar_cache_enabled:true", "cache_supported_case:true", "cache_hit:false", "caching_group:under1k", "repo_id:#{@repository.id}",
      ]

      navbar_metrics("issue").each do |metric_name|
        metrics = GitHub.dogstats.distributions(metric_name, tags: expected_tags)
        assert_equal 1, metrics.length
      end
    end

    test "it uses caching if the feature flags are enabled and it's a supported viewer/repo case -- cache HIT" do
      @user.stubs(:feature_enabled?).with(:magic_shell_caching).returns(false)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      # enable all flags
      GitHub.flipper[:navbar_hits].stubs(:enabled?).with(@user).returns(true)
      GitHub.flipper[:navbar_hits_details].stubs(:enabled?).with(@repository).returns(true)
      GitHub.flipper[:navbar_counter_caching].stubs(:enabled?).with(@repository).returns(true)

      # viewer is regular, non-spammy user case
      @user.stubs(:site_admin?).returns(false)
      @user.stubs(:spammy?).returns(false)
      @repository.stubs(:spammy?).returns(false)
      @repository.stubs(:owner_id).returns(@user.id + 1)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      provider.expects(:counter_cache_key).once.returns("navbar_cache-repo-test")
      GitHub.cache.expects(:get).with("navbar_cache-repo-test").once.returns(7898)
      @repository.expects(:open_issue_count_for).with(@user).never
      provider.expects(:counter_caching_ttl).never
      GitHub.cache.expects(:set).never

      assert_equal 7898, provider.open_issue_count

      expected_tags = [
        "logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false",
        "navbar_cache_enabled:true", "cache_supported_case:true", "cache_hit:true", "caching_group:over5k", "repo_id:#{@repository.id}",
      ]

      navbar_metrics("issue").each do |metric_name|
        metrics = GitHub.dogstats.distributions(metric_name, tags: expected_tags)
        assert_equal 1, metrics.length
      end
    end
  end

  context "#open_pull_request_count" do
    test "it returns the repository issue count for the user" do
      @repository.stubs(:open_pull_request_count_for).with(@user).returns(13)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      assert_equal provider.open_pull_request_count, 13
    end

    test "it emits dogstatsd metric for mysql calls if ff enabled " do
      enable_feature_flag(:navbar_hits)
      @repository.stubs(:open_pull_request_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_pull_request_count, 1
      navbar_metrics("pr").each do |metric_name|
        assert_equal 1, GitHub.dogstats.distributions(metric_name, tags: expected_tags).length
      end
    end

    test "it emits dogstatsd metric for mysql calls if ff enabled for staff user" do
      enable_feature_flag(:navbar_hits)
      @repository.stubs(:open_pull_request_count_for).with(@user).returns(1)
      @user.stubs(:employee?).returns(true)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_pull_request_count, 1
      navbar_metrics("pr").each do |metric_name|
        assert_equal 1, GitHub.dogstats.distributions(metric_name, tags: expected_tags).length
      end
    end

    test "it emits dogstatsd metric for mysql calls if ff enabled for anonymous requests" do
      enable_feature_flag(:navbar_hits)
      @repository.stubs(:open_pull_request_count_for).with(nil).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: nil)
      expected_tags = ["logged_in:false", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_pull_request_count, 1
      navbar_metrics("pr").each do |metric_name|
        assert_equal 1, GitHub.dogstats.distributions(metric_name, tags: expected_tags).length
      end
    end

    test "it does not emits dogstatsd metric for mysql calls if ff disabled" do
      @repository.stubs(:open_pull_request_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert_equal provider.open_pull_request_count, 1
      navbar_metrics("pr").each do |metric_name|
        assert_equal 0, GitHub.dogstats.distributions(metric_name).length
      end
    end

    test "it does not emits dogstatsd metric for mysql calls if ff disabled for anonymous requests" do
      @repository.stubs(:open_pull_request_count_for).with(nil).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: nil)

      assert_equal provider.open_pull_request_count, 1
      navbar_metrics("pr").each do |metric_name|
        assert_equal 0, GitHub.dogstats.distributions(metric_name).length
      end
    end
  end

  context "#open_project_count" do
    test "projects count includes only memex projects in enterprise", enterprise_only: true do
      @org_repository.stubs(:open_memex_projects_count_for).returns(2)
      create_list(:project, 3, owner: @org_repository)
      provider = NavigationTabsProviderComponent.new(current_user: nil, repository: @org_repository)
      assert_equal 2, provider.open_project_count
    end

    test "it emits dogstatsd metric for mysql calls if ff enabled " do
      enable_feature_flag(:navbar_hits)
      @repository.stubs(:open_memex_projects_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)
      expected_tags = ["logged_in:true", "viewer_site_admin:false", "viewer_spammy:false", "viewer_owner:false", "repo_spammy:false"]

      assert_equal provider.open_project_count, 1
      navbar_metrics("proj").each do |metric_name|
        assert_equal 1, GitHub.dogstats.distributions(metric_name, tags: expected_tags).length
      end
    end

    test "it does not emits dogstatsd metric for mysql calls if ff disabled" do
      @repository.stubs(:open_memex_projects_count_for).with(@user).returns(1)
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert_equal provider.open_project_count, 1
      navbar_metrics("proj").each do |metric_name|
        assert_equal 0, GitHub.dogstats.distributions(metric_name).length
      end
    end

    test "returns count of open memex projects" do
      @org_repository.stubs(:open_memex_projects_count_for).returns(2)
      create_list(:project, 3, owner: @org_repository)
      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @org_repository)
      assert_equal 2, provider.open_project_count
    end

    test "rescues ActiveRecord errors when counting memex projects" do
      create(:memex_project_link, source: @org_repository, memex_project: @memex)
      create(:memex_project_link, source: @org_repository, memex_project: @memex2)
      create_list(:project, 3, owner: @org_repository)

      @org_repository.stubs(:open_memex_projects_count_for).raises(ActiveRecord::StatementInvalid.new("memex queries are disabled in this test"))

      provider = NavigationTabsProviderComponent.new(current_user: @user, repository: @org_repository)
      assert_equal 0, provider.open_project_count
    end
  end

  context "#can_manage_code_security_settings?" do
    test "it returns false if the user is not logged in" do
      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: nil)

      refute provider.can_manage_code_security_settings?
    end

    test "it returns the value from SecurityProduct::Permissions::RepoAuthz when the repo does not have show config authzd enabled" do
      @repository.stubs(:show_config_authzd_enabled?).returns(false)
      SecurityProduct::Permissions::RepoAuthz.any_instance.stubs(:can_manage_security_products?).returns(true)

      provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

      assert provider.can_manage_code_security_settings?
    end

    context "when show config authzd is enabled" do
      test "it returns the value from batched layout authzd permissions for managing security products" do
        @repository.stubs(:show_config_authzd_enabled?).returns(true)
        @repository.stubs(:batched_layout_authzd_permissions).with(@user, :can_manage_security_products).returns(true)

        provider = NavigationTabsProviderComponent.new(repository: @repository, current_user: @user)

        assert provider.can_manage_code_security_settings?
      end
    end
  end
end
