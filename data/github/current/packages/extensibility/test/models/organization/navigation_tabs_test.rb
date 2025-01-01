# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationNavigationTabsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
    @billing_manager = create(:user)
    @member = create(:user)
    @non_member = create(:user)
    @org = create(:organization, admin: @user)
    @team_org = create(:team_org, admin: @user)
    @enterprise_org = create(:business_plus_org, admin: @user)
    @invoiced_org = create(:invoiced_org, :sponsors_invoiced, :with_sponsors_invoiced_plan_subscription, admin: @user)

    [@org, @invoiced_org].each do |org|
      org.billing.add_manager(@billing_manager, actor: org.admin)
      org.add_member(@member)
    end
  end

  setup do
    @tabs_builder = Organization::NavigationTabs.new(@org, current_user: @user)
    @tabs_builder_team_org = Organization::NavigationTabs.new(@team_org, current_user: @user)
    @tabs_builder_enterprise_org = Organization::NavigationTabs.new(@enterprise_org, current_user: @user)
  end

  context "#tabs" do
    test "it returns the essential tabs that are always present" do
      assert @tabs_builder.tabs.map(&:text).compact.any?
    end
  end

  context "#discussions_tab" do
    test "shows discussions tab when enabled" do
      GitHub.stubs(:discussions_available_on_platform?).returns(true)
      new_repo = create(:repository, owner: @org)
      create(:organization_discussion_config, organization: @org, repository: new_repo)
      refute_nil @tabs_builder.discussions_tab
    end

    test "doesn't show discussions tab when disabled" do
      GitHub.stubs(:discussions_available_on_platform?).returns(false)
      assert_nil @tabs_builder.discussions_tab
    end
  end

  context "#projects_tab" do
    test "shows tab when org projects are enabled" do
      @org.stubs(:organization_projects_enabled?).returns(true)
      refute_nil @tabs_builder.projects_tab
    end

    test "doesn't show tab when org projects are disabled" do
      @org.stubs(:organization_projects_enabled?).returns(false)
      assert_nil @tabs_builder.projects_tab
    end
  end

  context "#packages_tab" do
    test "shows packages tab when enabled" do
      PackageRegistryHelper.stubs(:show_packages?).returns(true)
      refute_nil @tabs_builder.packages_tab
    end

    test "doesn't show packages tab when disabled" do
      PackageRegistryHelper.stubs(:show_packages?).returns(false)
      assert_nil @tabs_builder.packages_tab
    end
  end

  context "#teams_tab" do
    test "doesn't show teams tab to users who aren't members of the org" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: create(:user))
      assert_nil tabs_builder.teams_tab
    end
  end

  context "#people_tab" do
    test "doesn't show people tab to billing managers who aren't members of the org" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: @billing_manager)
      assert_nil tabs_builder.people_tab
    end
  end

  context "#insights_tab" do
    test "shows insights tab when enabled" do
      @org.stubs(:insights_enabled?).returns(true)
      @org.stubs(:not_ghes_and_biz_plus?).returns(true)
      @org.stubs(:dependency_insights_visible?).returns(true)
      refute_nil @tabs_builder.insights_tab
    end

    test "doesn't show insights tab when disabled" do
      @org.stubs(:insights_enabled?).returns(false)
      assert_nil @tabs_builder.insights_tab
    end

    test "doesn't show insights tab to users who aren't members of the org" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: create(:user))
      @org.stubs(:insights_enabled?).returns(true)
      assert_nil tabs_builder.insights_tab
    end
  end

  context "#security_tab" do
    test "shows security tab to enterprise org members" do
      refute_nil @tabs_builder_enterprise_org.security_tab
      assert_includes @tabs_builder_enterprise_org.security_tab.href, "overview"
    end

    context "risk assessment" do
      test "points to the dashboard when security center is available" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_risk_assessment_available?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(true)
        refute_nil @tabs_builder_team_org.security_tab
        assert_includes @tabs_builder_team_org.security_tab.href, "overview"
      end

      test "not present when security center is not available and the user does not have the right role" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_risk_assessment_available?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(false)
        SecretScanning::AccessControl::SecretRiskAssessments.any_instance.stubs(:has_access_to_secret_risk_assessments?).returns(false)
        assert_nil @tabs_builder_team_org.security_tab
      end

      test "not present when security center is not available and the user has the right role but the plan is not teams" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_risk_assessment_available?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(false)
        SecretScanning::AccessControl::SecretRiskAssessments.any_instance.stubs(:has_access_to_secret_risk_assessments?).returns(true)
        Organization.any_instance.stubs(:plan).returns(GitHub::Plan.free)
        assert_nil @tabs_builder_team_org.security_tab
      end

      test "not present when security center is not available and the user has the right role but the org does not have advanced security purchased" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_risk_assessment_available?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(false)
        SecretScanning::AccessControl::SecretRiskAssessments.any_instance.stubs(:has_access_to_secret_risk_assessments?).returns(true)
        Organization.any_instance.stubs(:plan).returns(GitHub::Plan.business)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(false)
        assert_nil @tabs_builder_team_org.security_tab
      end

      test "points to the risk assessment tab when security center is not available, the business org has advanced security, and the user has the right role" do
        SecretScanning::Features::Org::TokenScanning.any_instance.stubs(:secret_risk_assessment_available?).returns(true)
        SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(false)
        SecretScanning::AccessControl::SecretRiskAssessments.any_instance.stubs(:has_access_to_secret_risk_assessments?).returns(true)
        Organization.any_instance.stubs(:plan).returns(GitHub::Plan.business)
        Organization.any_instance.stubs(:advanced_security_purchased?).returns(true)
        refute_nil @tabs_builder_team_org.security_tab
        assert_includes @tabs_builder_team_org.security_tab.href, "secret-risk-assessment"
      end
    end

    test "doesn't show security tab for free orgs", skip_enterprise: true do
      assert_nil @tabs_builder.security_tab
    end

    test "doesn't show security tab to users who can't access it" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: @non_member)
      ::SecurityCenter::SecurityFeatures.stubs(:security_center_available?).returns(true)
      assert_nil tabs_builder.security_tab
    end

    test "doesn't show security tab when user does not have access to secret risk assessments" do
      tabs_builder = Organization::NavigationTabs.new(@team_org, current_user: @non_member)
      assert_nil tabs_builder.security_tab
    end
  end

  context "#sponsoring_tab" do
    if GitHub.sponsors_enabled?
      test "renders for random when org has an active public sponsorship" do
        create(:sponsorship, sponsor: @org)
        random = create(:user)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: random)

        assert_equal 1, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for org admin when org has an active private sponsorship" do
        create(:sponsorship, :private, sponsor: @org)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @org.admin)

        assert_equal 1, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for billing manager when org has an active private sponsorship" do
        create(:sponsorship, :private, sponsor: @org)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @billing_manager)

        assert_equal 1, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for org member when org has an active private sponsorship" do
        create(:sponsorship, :private, sponsor: @org)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @member)

        assert_equal 1, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "does not render for random when org has an active private sponsorship" do
        create(:sponsorship, :private, sponsor: @org)
        random = create(:user)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: random)

        assert_nil tabs_builder.sponsoring_tab
      end

      test "renders for random when org only has an inactive public sponsorship" do
        sponsorship = create(:sponsorship, :from_org, sponsor: @org)
        org = sponsorship.sponsor
        random = create(:user)

        sponsorship.subscription_item.cancel!(actor: @org.admin, force: true)
        run_processor(GitHub::StreamProcessors::UserMetadata::SponsorProcessor.new)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: random)

        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for org admin when org only has an inactive private sponsorship" do
        sponsorship = create(:sponsorship, :private, :from_org, sponsor: @org)

        sponsorship.subscription_item.cancel!(actor: @org.admin, force: true)
        run_processor(GitHub::StreamProcessors::UserMetadata::SponsorProcessor.new)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @org.admin)

        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for billing manager when org only has an inactive private sponsorship" do
        sponsorship = create(:sponsorship, :private, :from_org, sponsor: @org)

        sponsorship.subscription_item.cancel!(actor: @org.admin, force: true)
        run_processor(GitHub::StreamProcessors::UserMetadata::SponsorProcessor.new)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @billing_manager)

        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for org member when org only has an inactive private sponsorship" do
        sponsorship = create(:sponsorship, :private, :from_org, sponsor: @org)

        sponsorship.subscription_item.cancel!(actor: @org.admin, force: true)
        run_processor(GitHub::StreamProcessors::UserMetadata::SponsorProcessor.new)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @member)

        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "does not render for random viewer when org only has an inactive private sponsorship" do
        sponsorship = create(:sponsorship, :private, :from_org, sponsor: @org)
        random = create(:user)

        sponsorship.subscription_item.cancel!(actor: @org.admin, force: true)
        run_processor(GitHub::StreamProcessors::UserMetadata::SponsorProcessor.new)

        tabs_builder = Organization::NavigationTabs.new(@org, current_user: random)

        assert_nil tabs_builder.sponsoring_tab
      end

      test "renders for org owner if invoiced billing is set up" do
        tabs_builder = Organization::NavigationTabs.new(@invoiced_org, current_user: @user)
        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@invoiced_org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "renders for billing manager if invoiced billing is set up" do
        tabs_builder = Organization::NavigationTabs.new(@invoiced_org, current_user: @billing_manager)
        assert_equal 0, tabs_builder.sponsoring_tab.count
        assert_equal "/orgs/#{@invoiced_org.display_login}/sponsoring", tabs_builder.sponsoring_tab.href
      end

      test "does not render for member if invoiced billing is set up" do
        tabs_builder = Organization::NavigationTabs.new(@invoiced_org, current_user: @member)
        assert_nil tabs_builder.sponsoring_tab
      end

      test "does not render for random user if invoiced billing is set up" do
        tabs_builder = Organization::NavigationTabs.new(@invoiced_org, current_user: @rando)
        assert_nil tabs_builder.sponsoring_tab
      end

      test "does not render for logged out user if invoiced billing is set up" do
        tabs_builder = Organization::NavigationTabs.new(@invoiced_org, current_user: nil)
        assert_nil tabs_builder.sponsoring_tab
      end
    else
      test "doesn't show sponsoring tab when GitHub Sponsors is disabled" do
        create(:user_metadata, user: @org, sponsoring_count: 1, sponsoring_public_and_private_count: 2)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: @user)

        assert_nil tabs_builder.sponsoring_tab
      end
    end
  end

  context "#settings_tab" do
    test "shows settings tab when user is an admin" do
      refute_nil @tabs_builder.settings_tab
    end

    test "doesn't show settings tab when user is not an admin" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: create(:user))
      assert_nil tabs_builder.settings_tab
    end

    test "shows settings tab to billing managers who aren't members of the org" do
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: @billing_manager)
      refute_nil tabs_builder.settings_tab
    end

    if GitHub.organization_moderators_enabled?
      test "shows settings tab to org moderators" do
        moderator = create(:user)
        @org.add_member(moderator)
        @org.moderation.add_moderator(moderator, actor: @user)
        tabs_builder = Organization::NavigationTabs.new(@org, current_user: moderator)
        refute_nil tabs_builder.settings_tab
      end
    end

    test "shows settings tab to users who can manage code security settings" do
      @org.add_member(@user)
      security_team = create(:security_manager_team, organization: @org)
      security_team.add_member(@user)
      tabs_builder = Organization::NavigationTabs.new(@org, current_user: @user)
      refute_nil tabs_builder.settings_tab
    end
  end
end
