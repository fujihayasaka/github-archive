# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::Permissions::BusinessAuthzEnumeratorTest < GitHub::IntegrationTestCase
  include ConditionalAccess::FilterTestHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    # Create business and orgs
    @business = create(:global_business)
    @orgs = [
      (@org1 = create(:business_plus_organization, business: @business, login: "org1")),
      (@org2 = create(:business_plus_organization, business: @business, login: "org2")),
      (@org3 = create(:business_plus_organization, business: @business, login: "org3")),
      (@non_business_org = (create(:organization, login: "non-biz-org") unless GitHub.single_business_environment?)),
    ].compact_blank!

    # Create repositories so default repo role querying works as expected...
    @orgs.each { |org| create(:repository, owner: org) }

    # ...but set default repo role to none for each org to start
    @orgs.each do |org|
      org.config.set(Configurable::DefaultRepositoryPermission::KEY, :none, org.admins.first)
      SyncOrganizationDefaultRepositoryPermissionJob.perform_now(org.id, Organization.name, org.admins.first.id)
    end

    # Create business owners
    @business_owner = create(:user, login: "business-owner")
    @business.add_owner(@business_owner, actor: nil)

    # Create security manager teams
    @org1_security_team = create(:security_manager_team, organization: @org1)

    # Create users with different role combinations

    # Org owners/admins
    @org1_admin = create(:user, login: "org1-admin").tap { |u| @org1.add_admin(u) }
    @org1_and_2_admin = create(:user, login: "org1-and-2-admin").tap do |u|
      @org1.add_admin(u)
      @org2.add_admin(u)
    end

    # Security manager team members
    @org1_security_manager_team_member = create(:user, login: "org1-security-manager-team-member").tap do |u|
      @org1.add_member(u)
      @org1_security_team.add_member(u)
    end

    @org2_security_manager = create(:user, login: "org2-security-manager").tap do |u|
      @org2.add_member(u)
      ::SecurityCenter::FeatureFlagHelper.stubs(:show_security_manager_in_org_role_assignment?).returns(true) # Allows assigning OSM to users
      @org2.grant_org_role(assignee: u, role: Role.security_manager_role)
      ::SecurityCenter::FeatureFlagHelper.unstub(:show_security_manager_in_org_role_assignment?)
    end

    # Users outside the business
    unless GitHub.single_business_environment?
      @non_business_org_admin = create(:user).tap { |u| @non_business_org.add_admin(u) }
      @non_business_user = create(:user)
    end

    @org1_collaborator = create(:user, login: "org1-collaborator")
    RepositoryInvitation.invite_to_repo_without_confirmation(@org1_collaborator, @org1.admins.first, @org1.repositories.first)

    @actions = [
      :read_repo,
      :read_code_scanning,
      :view_dependabot_alerts,
      :view_secret_scanning_alerts,
      :manage_security_products,
    ]
  end

  context "#initialize" do
    test "raises ArgumentError if actions array is empty" do
      assert_raises(ArgumentError) do
        SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor: @org1_admin,
          business: @business,
          actions: [],
          cap_filter: cap_authorizing_filter,
        )
      end
    end

    test "raises ArgumentError if actions is an empty symbol" do
      assert_raises(ArgumentError) do
        SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor: @org1_admin,
          business: @business,
          actions: :"",
          cap_filter: cap_authorizing_filter,
        )
      end
    end

    test "instantiates enumerator for single action" do
      assert_nothing_raised do
        SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor: @org1_admin,
          business: @business,
          actions: :my_action,
          cap_filter: cap_authorizing_filter,
        )
      end
    end

    test "instantiates enumerator for multiple actions" do
      assert_nothing_raised do
        SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor: @org1_admin,
          business: @business,
          actions: [:my_action, :my_other_action],
          cap_filter: cap_authorizing_filter,
        )
      end
    end
  end

  context "#authorized_orgs_where_actor_has_membership" do
    test "returns orgs where the user has membership" do
      enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_and_2_admin,
        business: @business,
        cap_filter: cap_authorizing_filter,
      )

      assert_same_elements [@org1, @org2], enumerator.authorized_orgs_where_actor_has_membership
    end

    test "returns authorized orgs where the user has membership" do
      enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_and_2_admin,
        business: @business,
        cap_filter: cap_authorizing_filter([@org2]),
      )

      assert_same_elements [@org2], enumerator.authorized_orgs_where_actor_has_membership
    end
  end

  context "#unauthorized_orgs_where_actor_has_membership" do
    test "returns unauthorized orgs where the user has membership" do
      enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_and_2_admin,
        business: @business,
        cap_filter: cap_unauthorizing_filter([@org2]),
      )

      assert_same_elements [@org2], enumerator.unauthorized_orgs_where_actor_has_membership
    end
  end

  context "#authorized_orgs_by_action" do
    test "returns hash that raises error when accessed with unevaluated action" do
      authorized_orgs_by_action = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_admin,
        business: @business,
        actions: :my_action,
        cap_filter: cap_authorizing_filter,
      ).authorized_orgs_by_action

      assert_nothing_raised do
        assert_same_elements [@org1], authorized_orgs_by_action[:my_action]
      end

      assert_raises(ArgumentError) do
        authorized_orgs_by_action[:my_other_action]
      end
    end

    test "returns empty hash if no action is provided" do
      enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_admin,
        business: @business,
        cap_filter: cap_authorizing_filter,
      )

      assert_query_count(0) do
        assert_equal({}, enumerator.authorized_orgs_by_action)
      end
    end

    context "all orgs are authorized" do
      unless GitHub.single_business_environment?
        test "returns empty arrays for users outside the provided business" do
          [@non_business_org_admin, @non_business_user].each do |actor|
            enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
              actor:,
              business: @business,
              actions: @actions,
              cap_filter: cap_authorizing_filter,
            )

            assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
            enumerator.authorized_orgs_by_action.each do |k, v|
              assert_empty v, "Expected empty array for user #{actor.name} for action #{k}"
            end
          end
        end
      end

      test "returns empty arrays for business owners without org membership" do
        actor = @business_owner
        enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor:,
          business: @business,
          actions: @actions,
          cap_filter: cap_authorizing_filter,
        )

        assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
        enumerator.authorized_orgs_by_action.each do |k, v|
          assert_empty v, "Expected empty array for user #{actor.name} for action #{k}"
        end
      end

      test "returns correct organizations for org admins" do
        {
          @org1_admin => [@org1],
          @org1_and_2_admin => [@org1, @org2],
        }.each do |actor, expected_orgs|
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            assert_same_elements expected_orgs, v, "Expected user #{actor.name} to have access to #{expected_orgs.map(&:name)} for action #{k}"
          end
        end
      end

      test "returns correct organizations for security managers" do
        {
          @org1_security_manager_team_member => [@org1],
          @org2_security_manager => [@org2],
        }.each do |actor, expected_orgs|
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            assert_same_elements expected_orgs, v, "Expected user #{actor.name} to have access to #{expected_orgs.map(&:name)} for action #{k}"
          end
        end
      end

      test "returns empty arrays for org members without roles granting given actions" do
        org1_member = create(:user, login: "org1-member").tap { |u| @org1.add_member(u) }
        org2_member = create(:user, login: "org2-member").tap { |u| @org2.add_member(u) }

        [org1_member, org2_member].each do |actor|
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            assert_empty v, "Expected empty array for user #{actor.name} for action #{k}"
          end
        end
      end

      test "returns correct organizations for org members with custom roles granting given actions" do
        org1_member = create(:user, login: "org1-member").tap do |u|
          @org1.add_member(u)
          grant_custom_org_role(role_name: "custom_ss_role", user: u, target: @org1, fgps: [:view_secret_scanning_alerts], base_role: :read)
        end

        org2_member = create(:user, login: "org2-member").tap do |u|
          @org2.add_member(u)
          grant_custom_org_role(role_name: "custom_dbot_role", user: u, target: @org2, fgps: [:view_dependabot_alerts], base_role: :read)
        end

        org1_and_2_member = create(:user, login: "org1-and-2-member").tap do |u|
          @org1.add_member(u)
          @org2.add_member(u)
          grant_custom_org_role(role_name: "custom_cs_role1", user: u, target: @org1, fgps: [:read_code_scanning], base_role: :read)
          grant_custom_org_role(role_name: "custom_cs_role2", user: u, target: @org2, fgps: [:read_code_scanning], base_role: :read)
        end

        actions = [:read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts]

        {
          org1_member => Hash.new([]).tap { |h| h[:view_secret_scanning_alerts] = [@org1] },
          org2_member => Hash.new([]).tap { |h| h[:view_dependabot_alerts] = [@org2] },
          org1_and_2_member => Hash.new([]).tap { |h| h[:read_code_scanning] = [@org1, @org2] },
        }.each do |actor, expected|
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            assert_same_elements expected[k], v, "Expected user #{actor.name} to have access to #{expected[k].map(&:name)} for action #{k}"
          end
        end
      end

      test "returns correct organizations for org members with custom org roles that have base repo roles granting given actions" do
        expected = {
          read: [:read_repo],
          triage: [:read_repo],
          write: [:read_repo, :read_code_scanning, :view_dependabot_alerts],
          maintain: [:read_repo, :read_code_scanning, :view_dependabot_alerts],
          admin: [:read_repo, :read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts, :manage_security_products],
        }

        expected.each do |base_role, expected_actions|
          org1_member = create(:user, login: "org1-member-#{base_role}").tap do |u|
            @org1.add_member(u)
            grant_custom_org_role(role_name: "custom_role_base_#{base_role}", user: u, target: @org1, base_role:)
          end

          actor = org1_member
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            if expected_actions.include?(k)
              assert_same_elements [@org1], v, "Expected user #{actor.name} to have access to #{@org1.name} for action #{k} from base role #{base_role}"
            else
              assert_empty v, "Expected empty array for user #{actor.name} for action action #{k} from base role #{base_role}"
            end
          end
        end
      end

      test "returns correct organizations for org members in orgs with default repo roles granting given actions" do
        expected = {
          none: [],
          read: [:read_repo],
          write: [:read_repo, :read_code_scanning, :view_dependabot_alerts],
          admin: [:read_repo, :read_code_scanning, :view_dependabot_alerts, :view_secret_scanning_alerts, :manage_security_products],
        }

        org1_member = create(:user, login: "org1-member").tap { |u| @org1.add_member(u) }
        expected.each do |default_role, expected_actions|
          # Setting for all orgs just to confirm only the org the user is a member of is considered
          @orgs.each do |org|
            org.config.set(Configurable::DefaultRepositoryPermission::KEY, default_role, org.admins.first)
            SyncOrganizationDefaultRepositoryPermissionJob.perform_now(org.id, Organization.name, org.admins.first.id)
          end

          actor = org1_member
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter: cap_authorizing_filter,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            if expected_actions.include?(k)
              assert_same_elements [@org1], v, "Expected user #{actor.name} to have access to #{@org1.name} for action #{k} from default repo role #{default_role}"
            else
              assert_empty v, "Expected empty array for user #{actor.name} for action action #{k} from default repo role #{default_role}"
            end
          end
        end
      end

      test "returns correct organizations for collaborators ignoring default repo roles" do
        @org1.config.set(Configurable::DefaultRepositoryPermission::KEY, :admin, @org1.admins.first)
        SyncOrganizationDefaultRepositoryPermissionJob.perform_now(@org1.id, Organization.name, @org1.admins.first.id)

        grant_custom_org_role(role_name: "custom_role", user: @org1_collaborator, target: @org1, fgps: [:read_code_scanning], base_role: :read)

        actor = @org1_collaborator
        enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor:,
          business: @business,
          actions: @actions,
          cap_filter: cap_authorizing_filter,
        )

        assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
        enumerator.authorized_orgs_by_action.each do |k, v|
          if k.in? [:read_repo, :read_code_scanning]
            assert_same_elements [@org1], v, "Expected user #{actor.name} to have access to #{@org1.name} for action #{k}"
          else
            assert_empty v, "Expected empty array for user #{actor.name} for action #{k}"
          end
        end
      end
    end

    context "some orgs are authorized" do
      test "returns organizations authorized by cap filter" do
        actor = @org1_and_2_admin

        {
          cap_authorizing_filter => [@org1, @org2],
          cap_authorizing_filter([@org1]) => [@org1],
          cap_authorizing_filter([@org2]) => [@org2],
          cap_authorizing_filter([@org3]) => [],
          cap_unauthorizing_filter => [],
        }.each do |cap_filter, expected_orgs|
          enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
            actor:,
            business: @business,
            actions: @actions,
            cap_filter:,
          )

          assert_same_elements @actions, enumerator.authorized_orgs_by_action.keys
          enumerator.authorized_orgs_by_action.each do |k, v|
            assert_same_elements expected_orgs, v, "Expected user #{actor.name} to have access to #{@org1.name} for action #{k}"
          end
        end
      end
    end
  end

  context "#unauthorized_orgs_for_actions" do
    test "returns empty array if no action is provided" do
      enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
        actor: @org1_admin,
        business: @business,
        cap_filter: cap_authorizing_filter,
      )

      assert_query_count(0) do
        assert_equal([], enumerator.unauthorized_orgs_for_actions)
      end
    end

    test "returns organizations unauthorized by cap filter for orgs where the user has the provided actions" do
      actor = @org1_and_2_admin

      {
        cap_authorizing_filter => [],
        cap_authorizing_filter([@org1]) => [@org2],
        cap_authorizing_filter([@org2]) => [@org1],
        cap_authorizing_filter([@org3]) => [@org1, @org2],
        cap_unauthorizing_filter => [@org1, @org2],
      }.each do |cap_filter, expected_orgs|
        enumerator = SecurityProduct::Permissions::BusinessAuthzEnumerator.new(
          actor:,
          business: @business,
          actions: @actions,
          cap_filter:,
        )

        assert_same_elements expected_orgs, enumerator.unauthorized_orgs_for_actions
      end
    end
  end
end
