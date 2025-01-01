# typed: true
# frozen_string_literal: true

require "test_helper"

class ProfilesOrganizationLayoutDataTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @profile_organization = create(:organization, admin: @owner)
    @viewer = create(:credit_card_user, plan_subscription: create(:billing_plan_subscription))
    @member = create(:user)
    @profile_organization.add_member(@member)
    @profile_organization.publicize_member(@owner)
  end

  setup do
    GitHub.flipper[:default_org_profiles_to_public_repos].disable(@viewer)
    GitHub.flipper[:default_org_profiles_to_public_repos].disable(@profile_organization)
  end

  context ".preload" do
    test "it prefetches all of the data in the minimal amount of queries" do
      assert_max_query_count(25) do
        Profiles::Organization::LayoutData.preload(
          profile_organization: @profile_organization,
          viewer: @viewer,
          active_tab: :overview,
        )
      end
    end

    test "no queries are made after the data is preloaded" do
      layout_data = Profiles::Organization::LayoutData.preload(
        profile_organization: @profile_organization,
        viewer: @viewer,
        active_tab: :overview,
      )

      assert_max_query_count(0) do
        Profiles::Organization::LayoutData::METHODS_TO_PRELOAD.each do |method|
          layout_data.send(method)
        end
      end
    end
  end

  context "#organization_members" do
    test "organization owner can see all organization members" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @owner,
        active_tab: :overview,
      )

      assert_equal data.organization_members.count, 2
    end

    test "organization member can see all organization members" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @member,
        active_tab: :overview,
      )

      assert_equal data.organization_members.count, 2
    end

    test "external viewer can only see public organization members" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @viewer,
        active_tab: :overview,
      )

      assert_equal data.organization_members.count, 1
      assert_equal data.organization_members.first, @owner
    end

    test "limits returned members" do
      Profiles::Organization::LayoutData.stub_const(:SIDEBAR_MEMBERS_LIMIT, 1) do
        data = Profiles::Organization::LayoutData.new(
          profile_organization: @profile_organization,
          viewer: @member,
          active_tab: :overview,
        )
        assert_equal [@owner], data.organization_members, "should have returned a single public member"
      end
    end

    test "limits queries per table even when returning public and private members" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @member,
        active_tab: :overview,
      )

      members = assert_query_count_per_table({ users: 1 }) do
        data.organization_members
      end

      public_member = members.detect { |member| @profile_organization.public_member?(member) }
      refute_nil public_member, "should have included a public member of the org"
      private_member = members.detect { |member| !@profile_organization.public_member?(member) }
      refute_nil private_member, "should have included a private member of the org"
    end

    test "sorts public and private members together, ordered by ID ascending" do
      public_member2 = create(:user)
      @profile_organization.add_member(public_member2)
      @profile_organization.publicize_member(public_member2)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @member,
        active_tab: :overview,
      )

      assert_equal [@owner, @member, public_member2], data.organization_members
    end

    test "does not include private members when viewer can't see them and results are limited" do
      public_member2 = create(:user)
      @profile_organization.add_member(public_member2)
      @profile_organization.publicize_member(public_member2)

      other_private_member = create(:user)
      @profile_organization.add_member(other_private_member)

      public_member3 = create(:user)
      @profile_organization.add_member(public_member3)
      @profile_organization.publicize_member(public_member3)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: nil,
        active_tab: :overview,
      )

      Profiles::Organization::LayoutData.stub_const(:SIDEBAR_MEMBERS_LIMIT, 2) do
        assert_equal [@owner, public_member2], data.organization_members,
          "should have returned limited number of public members preferring the lowest IDs first"
      end
    end
  end

  context "#direct_or_team_member?" do
    test "returns true for org member viewer" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @member,
        active_tab: :overview,
      )
      assert_predicate data, :direct_or_team_member?
    end

    test "returns true for org admin viewer" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @owner,
        active_tab: :overview,
      )
      assert_predicate data, :direct_or_team_member?
    end

    test "returns true for team member viewer" do
      team_member = create(:user)
      team = create(:team, privacy: :closed, organization: @profile_organization)
      team.add_member(team_member)
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: team_member,
        active_tab: :overview,
      )
      assert_predicate data, :direct_or_team_member?
    end

    test "returns false for viewer who is neither an org nor team member" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: @viewer,
        active_tab: :overview,
      )
      refute_predicate data, :direct_or_team_member?
    end

    test "returns false for anonymous viewer" do
      data = Profiles::Organization::LayoutData.new(
        profile_organization: @profile_organization,
        viewer: nil,
        active_tab: :overview,
      )
      refute_predicate data, :direct_or_team_member?
    end
  end

  context "#show_ghas_trial_upsell_banner?" do
    test "shows banner on overview page when non-enterprise, ghas-eligible org is viewed by org admin" do
      org = create(:organization, admin: @owner)
      org.enable_advanced_security_eligiblity_for_entity(actor: @owner)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: org,
        viewer: @owner,
        active_tab: :overview,
      )

      assert_predicate data, :show_ghas_trial_upsell_banner?
    end

    test "shows banner on overview page enterprise org is eligible for self-serve trial" do
      business = create(:billing_plan_subscription, :business_owned).business
      business_owner = business.owners.first
      child_org = create(:enterprise_linked_organization, admin: business_owner, business: business)

      child_org.enable_advanced_security_eligiblity_for_entity(actor: business_owner)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: child_org,
        viewer: business_owner,
        active_tab: :overview,
      )
      assert_predicate data, :show_ghas_trial_upsell_banner?
    end

    test "does not show banner when ghas-eligible org is viewed by non-admin" do
      org = create(:organization, admin: @owner)
      org.enable_advanced_security_eligiblity_for_entity(actor: @owner)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: org,
        viewer: @user,
        active_tab: :overview,
      )

      refute_predicate data, :show_ghas_trial_upsell_banner?
    end

    test "does not show banner when org, is not ghas-eligible" do
      org = create(:organization, admin: @owner)

      data = Profiles::Organization::LayoutData.new(
        profile_organization: org,
        viewer: @owner,
        active_tab: :overview,
      )

      refute_predicate data, :show_ghas_trial_upsell_banner?
    end
  end if GitHub.billing_enabled?

  if GitHub.sponsors_enabled?
    context "#show_github_sponsor_recognition?" do
      test "true for publicly sponsoring credit card organization" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        create(:sponsorship, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: @owner,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "true for publicly sponsoring invoiced organization" do
        invoiced_org = create(:invoiced_org, :sponsors_invoiced, admin: @owner)
        create(:sponsorship, sponsor: invoiced_org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: invoiced_org,
          viewer: @owner,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "true for publicly sponsoring credit card organization when viewer is anonymous" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        create(:sponsorship, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: nil,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "true for privately sponsoring credit card organization when viewer is org admin" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        create(:sponsorship, :private, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: @owner,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "true for privately sponsoring credit card organization when viewer is org member" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        create(:sponsorship, :private, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: @owner,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "true for privately sponsoring credit card organization when viewer is org billing manager" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        billing_manager = create(:user)
        org.billing.add_manager(billing_manager, actor: @owner)
        create(:sponsorship, :private, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: billing_manager,
          active_tab: :overview,
        )

        assert_predicate data, :show_github_sponsor_recognition?
      end

      test "false for privately sponsoring credit card organization when viewer is random user" do
        org = create(:credit_card_org, plan_subscription: create(:billing_plan_subscription), admin: @owner)
        create(:sponsorship, :private, sponsor: org)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: org,
          viewer: @viewer,
          active_tab: :overview,
        )

        refute_predicate data, :show_github_sponsor_recognition?
      end

      test "false for non-sponsoring credit card organization" do
        data = Profiles::Organization::LayoutData.new(
          profile_organization: @profile_organization,
          viewer: @owner,
          active_tab: :overview,
        )

        refute_predicate data, :show_github_sponsor_recognition?
      end
    end
  end

  context "show_developer_program_member_badge?" do
    if GitHub.enterprise?
      test "doesn't show developer program member badge in Enterprise" do
        data = Profiles::Organization::LayoutData.new(
          profile_organization: @profile_organization,
          viewer: @owner,
          active_tab: :overview,
        )

        refute_predicate data, :show_developer_program_member_badge?
      end
    else
      test "shows developer program member badge when org is developer program member" do
        program_membership = create(:developer_program_membership, user: @profile_organization)

        data = Profiles::Organization::LayoutData.new(
          profile_organization: @profile_organization,
          viewer: @owner,
          active_tab: :overview,
        )

        assert_predicate data, :show_developer_program_member_badge?
      end

      test "doesn't show developer program member badge when org isn't developer program member" do
        data = Profiles::Organization::LayoutData.new(
          profile_organization: @profile_organization,
          viewer: @owner,
          active_tab: :overview,
        )

        refute_predicate data, :show_developer_program_member_badge?
      end
    end
  end
end
