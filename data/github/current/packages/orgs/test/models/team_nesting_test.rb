# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamModelNestingTeamsTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @org = create :organization, plan: "bronze", admin: @owner
    only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @owner) }
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    self.perform_enqueued_jobs = true # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
  end

  context "team hierarchies" do
    test "should validate that a team parent is in the org" do
      team_employees = create :team, organization: @org, privacy: :closed
      team_engineering = create :team, organization: @org, privacy: :closed

      other_org = create :organization, admin: @owner
      team_from_another_org = create :team, organization: other_org, privacy: :closed

      team_engineering.parent_team = team_employees

      assert team_engineering.valid?

      team_engineering.parent_team = team_from_another_org

      refute team_engineering.valid?
      assert_equal "must be a member of the same org", team_engineering.errors[:parent_team_id].first
    end

    test "should validate that a cycle is not created" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      team_employees.parent_team = team_identity

      refute team_employees.valid?
      assert_equal "can't be a child of the current team", team_employees.errors[:parent_team_id].first

      # parent team can not be itself. That's also a cycle
      team_employees.parent_team = team_employees

      refute team_employees.valid?
      assert_equal "can't be a child of the current team", team_employees.errors[:parent_team_id].first
    end

    test "should validate that parent team is not secret" do
      team_engineering = create :team, organization: @org, privacy: :secret, name: "engineering"
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity"

      #child can't be secret
      team_identity.parent_team = team_engineering
      refute team_identity.valid?
      assert_equal "can't be a secret team", team_identity.errors[:parent_team_id].first
    end

    test "should validate that team is not secret if it's a parent or child" do
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering"
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      assert team_identity.valid?

      #child can't be secret
      team_identity.privacy = :secret
      refute team_identity.valid?
      assert_equal "can't be secret for a child team", team_identity.errors[:visibility].first

      #reset
      team_identity.privacy = :closed

      assert team_engineering.valid?

      #parent can't be secret (even it it's a top level team)
      team_engineering.privacy = :secret
      refute team_engineering.valid?
      assert_equal "can't be secret for a parent team", team_engineering.errors[:visibility].first
    end

    test "should move node to root when setting parent id to nil" do
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering"
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      team_identity.parent_team = nil

      assert_nil team_identity.reload.parent_team_id
    end

    test "should move from one parent to another" do
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering"
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      team_design = create :team, organization: @org, privacy: :closed, name: "design"
      team_identity.parent_team = team_design

      assert_equal team_design.id, team_identity.reload.parent_team_id
    end

    test "child_teams return direct child teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_workflow = create :team, organization: @org, privacy: :closed, name: "workflow", parent_team_id: team_engineering.id

      assert_same_elements [team_engineering], team_employees.child_teams
    end

    test "child_teams does not return deleted child teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_deleted = create :team, organization: @org, privacy: :closed, name: "deleted", deleted: true, parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_workflow = create :team, organization: @org, privacy: :closed, name: "workflow", parent_team_id: team_engineering.id

      assert_same_elements [team_engineering], team_employees.child_teams
    end

    test "ancestors return all parent teams for multiple levels of nesting sorted by seniority" do
      team_great_grandparent = create :team, organization: @org, privacy: :closed, name: "great grandparent"
      team_grandparent = create :team, organization: @org, privacy: :closed, name: "grandparent", parent_team_id: team_great_grandparent.id
      team_parent = create :team, organization: @org, privacy: :closed, name: "parent", parent_team_id: team_grandparent.id
      team_child = create :team, organization: @org, privacy: :closed, name: "child", parent_team_id: team_parent.id
      team_rando = create :team, organization: @org, privacy: :closed, name: "rando"

      assert_same_elements [team_great_grandparent, team_grandparent, team_parent], team_child.ancestors
      refute team_child.ancestors.include? team_rando
    end

    test "ancestors does not return deleted parent teams" do
      team_great_great_grandparent = create :team, organization: @org, privacy: :closed, name: "great great grandparent", deleted: true
      team_great_grandparent = create :team, organization: @org, privacy: :closed, name: "great grandparent", parent_team_id: team_great_great_grandparent.id
      team_grandparent = create :team, organization: @org, privacy: :closed, name: "grandparent", parent_team_id: team_great_grandparent.id
      team_parent = create :team, organization: @org, privacy: :closed, name: "parent", parent_team_id: team_grandparent.id
      team_child = create :team, organization: @org, privacy: :closed, name: "child", parent_team_id: team_parent.id

      assert_same_elements [team_great_grandparent, team_grandparent, team_parent], team_child.ancestors
    end

    test "descendants return all child teams for multiple levels of nesting" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_workflow = create :team, organization: @org, privacy: :closed, name: "workflow", parent_team_id: team_engineering.id

      assert_same_elements [team_engineering, team_identity, team_workflow], team_employees.descendants
    end

    test "descendants does not return deleted child teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_deleted = create :team, organization: @org, privacy: :closed, name: "deleted", deleted: true, parent_team_id: team_engineering.id
      team_workflow = create :team, organization: @org, privacy: :closed, name: "workflow", parent_team_id: team_engineering.id

      assert_same_elements [team_engineering, team_identity, team_workflow], team_employees.descendants
    end

    test "descendants_depth_first traverses the tree in depth-firt order" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_pizza_penguin = create :team, organization: @org, privacy: :closed, name: "pizza_penguin", parent_team_id: team_identity.id

      assert_equal [team_pizza_penguin, team_identity, team_engineering], team_employees.descendants_depth_first
    end

    test "can set empty parent id using update_attributes or setter" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: ""
      assert_nil team_engineering.parent_team

      team_design = create :team, organization: @org, privacy: :closed, name: "design", parent_team_id: team_employees.id

      team_design.update(parent_team_id: "")
      assert_nil team_design.reload.parent_team

      team_design.update(parent_team_id: team_employees.id)
      refute_nil team_design.reload.parent_team

      team_design.parent_team_id = ""
      assert team_design.save
      assert_nil team_design.reload.parent_team
    end

    test "set team parent id to nil" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_design = create :team, organization: @org, privacy: :closed, name: "design", parent_team_id: team_employees.id
      refute_nil team_design.reload.parent_team

      team_design.parent_team_id = nil
      assert team_design.save
      team_design.reload
      assert_nil team_design.parent_team_id
    end

    test "can destroy parent teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id

      assert team_employees.destroy
      refute_equal "Parent teams can not be deleted", team_employees.errors[:base].first
    end

    test "root teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      create :team, organization: @org, privacy: :closed, name: "design", parent_team_id: team_employees.id
      create :team, organization: @org, privacy: :closed, name: "sales", parent_team_id: team_employees.id

      assert_equal 1, team_employees.organization.root_teams.size
    end
  end

  context "#descendant_or_self_members" do
    test "returns members from child teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      employee_member = create(:user)
      engineering_member = create(:user)
      identity_member = create(:user)
      team_employees.add_member(employee_member)
      team_engineering.add_member(engineering_member)
      team_identity.add_member(identity_member)

      descendant_members = team_employees.descendant_or_self_members
      assert_includes descendant_members, engineering_member
      assert_includes descendant_members, identity_member
    end

    test "returns members from the current team" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      employee_member = create(:user)
      engineering_member = create(:user)
      identity_member = create(:user)
      team_employees.add_member(employee_member)
      team_engineering.add_member(engineering_member)
      team_identity.add_member(identity_member)

      descendant_members = team_employees.descendant_or_self_members
      assert_includes descendant_members, employee_member
    end

    test "returns members who are admins on descendants or self when action: :admin" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      employee_member = create(:user)
      engineering_member = create(:user)
      identity_member = create(:user)
      team_employees.add_member(employee_member)
      team_employees.promote_maintainer(employee_member)
      team_engineering.add_member(engineering_member)
      team_engineering.add_member(engineering_member)
      team_identity.add_member(identity_member)
      team_identity.promote_maintainer(identity_member)

      descendant_members = team_employees.descendant_or_self_members(action: :admin)
      assert_same_elements [employee_member, identity_member], descendant_members
    end
  end

  context "#descendant_members" do
    test "doesn't return members from the current team" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      employee_member = create(:user)
      engineering_member = create(:user)
      identity_member = create(:user)
      team_employees.add_member(employee_member)
      team_engineering.add_member(engineering_member)
      team_identity.add_member(identity_member)

      descendant_members = team_employees.descendant_members
      assert_same_elements descendant_members, [engineering_member, identity_member]
    end

    test "returns members who are admins on descendants when action: :admin" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      employee_member = create(:user)
      engineering_member = create(:user)
      identity_member = create(:user)
      team_employees.add_member(employee_member)
      team_employees.promote_maintainer(employee_member)
      team_engineering.add_member(engineering_member)
      team_engineering.add_member(engineering_member)
      team_identity.add_member(identity_member)
      team_identity.promote_maintainer(identity_member)

      descendant_members = team_employees.descendant_members(action: :admin)
      assert_same_elements [identity_member], descendant_members
    end
  end

  context "#descendants_where_user_is_a_member" do
    test "returns descendant teams where the user is a member (direct or indirect)" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      identity_member = create(:user)
      team_identity.add_member(identity_member)

      teams = team_employees.descendants_where_user_is_a_member(identity_member)
      assert_same_elements [team_engineering, team_identity], teams
    end

    test "does not return deleted descendant teams" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id
      team_deleted = create :team, organization: @org, privacy: :closed, name: "deleted", deleted: true, parent_team_id: team_engineering.id

      identity_member = create(:user)
      team_identity.add_member(identity_member)

      teams = team_employees.descendants_where_user_is_a_member(identity_member)
      assert_same_elements [team_engineering, team_identity], teams
    end

    test "can handle a team with no descendants" do
      team = create :team, organization: @org, privacy: :closed, name: "employees"
      member = create(:user)
      team.add_member(member)

      teams = team.descendants_where_user_is_a_member(member)
      assert_same_elements [], teams
    end
  end

  context "#descendants_without_members" do
    test "returns descendant teams where there are no members (direct or indirect)" do
      team_employees = create :team, organization: @org, privacy: :closed, name: "employees"
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity = create :team, organization: @org, privacy: :closed, name: "identity", parent_team_id: team_engineering.id

      engineering_member = create(:user)
      team_engineering.add_member(engineering_member)

      teams = team_employees.descendants_without_members
      assert_same_elements [team_identity], teams
    end
  end

  context "permissions and memberships" do
    test "flow down the hierarchy: A user can access repositories accesibles from an ancestor team" do
      # Now we have this hierarchy:
      #
      #              marketing
      #            /
      #  employees
      #            \
      #              engineering - identity
      #
      team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
      team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity    = create :team, organization: @org, privacy: :closed, name: "identity",    parent_team_id: team_engineering.id

      user = create(:user)

      # and marketing has it's repo
      repo_for_marketing = create :private_repository, :minimal, owner: @org
      team_marketing.add_repository(repo_for_marketing, :pull)

      # and engineering has it's repo
      repo_for_engineering = create :private_repository, :minimal, owner: @org
      team_engineering.add_repository(repo_for_engineering, :pull)

      # initially the user doesn't have access to any of the former repos
      refute_able user, :read, repo_for_marketing
      refute_able user, :read, repo_for_engineering

      # we add the user to identity, hence expecting to have access to the engineering
      # repository, but not to the marketing repository.
      team_identity.add_member user

      refute_able user, :read, repo_for_marketing
      assert_able user, :read, repo_for_engineering

      # however the user does not belong to those ancestor teams
      refute team_employees.member_ids.include?(user.id)
      refute team_engineering.member_ids.include?(user.id)
      assert team_identity.member_ids.include?(user.id)
    end

    test "when a user is removed from a team, transitive permissions are deleted" do
      team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
      team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
      team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
      team_identity    = create :team, organization: @org, privacy: :closed, name: "identity",    parent_team_id: team_engineering.id

      # user added to the team needs to be outside of the org, otherwise he would be able to see any closed team
      user = create(:user)

      team_identity.add_member user
      team_employees.add_member user

      # we have direct access to the teams the user has been directly added to
      # and indirect access to the teams up in the hierarchy
      assert_accessible(user, team_identity)
      assert_accessible(user, team_employees)
      assert_accessible(user, team_engineering)

      # when we remove the user, we revoke the abilities granted directly on that team
      # and indirectly on their ancestors.
      # Other direct and indirect abilities granted remain untouched.
      team_identity.remove_member user
      refute_accessible(user, team_identity)
      refute_accessible(user, team_engineering)
      assert_accessible(user, team_employees)
    end

    context "#destroy (destroying hierarchies of teams)" do
      test "when a team a user has transitive permissions on is deleted, children teams are deleted, and hence permissions" do
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id

        lizz = create(:user, login: "lizz")
        team_opensource.add_member lizz
        team_engineering.add_member lizz

        assert_accessible(lizz, team_marketing)
        assert_accessible(lizz, team_opensource)
        assert_accessible(lizz, team_engineering)
        assert_accessible(lizz, team_employees)

        assert team_marketing.destroy

        refute_accessible(lizz, team_marketing)
        refute_accessible(lizz, team_opensource)
        assert_accessible(lizz, team_engineering)
        assert_accessible(lizz, team_employees)

        refute Team.exists?(team_marketing.id)
        refute Team.exists?(team_opensource.id)
        assert Team.exists?(team_engineering.id)
        assert Team.exists?(team_employees.id)
      end
    end

    context "moving teams to other ancestors" do
      test "materialized indirect abilities are recalculated when team moved is leaf" do
        mike = create(:user, login: "mike")

        # Now we have this hierarchy:
        #
        #              marketing - opensource
        #            /
        #  employees
        #            \
        #              engineering
        #
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id

        assert_equal [team_opensource], team_marketing.descendants
        assert_equal [], team_engineering.descendants
        assert_equal [team_employees, team_marketing], team_opensource.ancestors

        team_opensource.add_member mike

        assert_accessible(mike, team_opensource)
        assert_accessible(mike, team_marketing)
        assert_accessible(mike, team_employees)
        refute_accessible(mike, team_engineering)

        # And we want to move opensource to engineering, leading to this hiearchy:
        #
        #              marketing
        #            /
        #  employees
        #            \
        #              engineering - opensource
        #
        team_opensource.parent_team = team_engineering

        assert_equal [], team_marketing.descendants
        assert_equal [team_opensource], team_engineering.descendants
        assert_equal [team_employees, team_engineering], team_opensource.ancestors

        assert_accessible(mike, team_opensource)
        assert_accessible(mike, team_engineering)
        assert_accessible(mike, team_employees)
        refute_accessible(mike, team_marketing)

        assert_equal [1], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_deleted").map(&:value)
        assert_equal [1], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_created").map(&:value)
      end

      test "moving a node that's not a leaf" do
        aki = create(:user, login: "aki")
        brandon = create(:user, login: "brandon")
        katrina = create(:user, login: "katrina")

        # Now we have this hierarchy:
        #
        #              marketing - opensource
        #            /
        #  employees
        #            \
        #              engineering
        #
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id

        team_marketing.add_member  aki
        team_marketing.add_member  brandon
        team_opensource.add_member brandon # Yeah, he is a direct member of both teams
        team_opensource.add_member katrina

        refute_accessible(aki, team_opensource)
        assert_accessible(aki, team_marketing)
        assert_accessible(aki, team_employees)
        refute_accessible(aki, team_engineering)

        assert_accessible(brandon, team_opensource)
        assert_accessible(brandon, team_marketing)
        assert_accessible(brandon, team_employees)
        refute_accessible(brandon, team_engineering)

        assert_accessible(katrina, team_opensource)
        assert_accessible(katrina, team_marketing)
        assert_accessible(katrina, team_employees)
        refute_accessible(katrina, team_engineering)

        # And we want to move marketing to engineering (because why not!), leading to this hiearchy:
        #
        #  employees - engineering - marketing - opensource
        #
        team_marketing.parent_team = team_engineering

        refute_accessible(aki, team_opensource)
        assert_accessible(aki, team_marketing)
        assert_accessible(aki, team_employees)
        assert_accessible(aki, team_engineering)

        assert_accessible(brandon, team_opensource)
        assert_accessible(brandon, team_marketing)
        assert_accessible(brandon, team_employees)
        assert_accessible(brandon, team_engineering)

        assert_accessible(katrina, team_opensource)
        assert_accessible(katrina, team_marketing)
        assert_accessible(katrina, team_employees)
        assert_accessible(katrina, team_engineering)

        assert_equal [0], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_deleted").map(&:value)
        assert_equal [4], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_created").map(&:value)
      end

      test "moving a node that's not a leaf with more than one children" do
        mike = create(:user, login: "mike")
        jane = create(:user, login: "jane")

        # Now we have this hierarchy:
        #
        #                          creativity
        #                         /
        #              marketing
        #            /            \
        #  employees                opensource
        #            \
        #              engineering
        #
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id
        team_creativity  = create :team, organization: @org, privacy: :closed, name: "creativity",  parent_team_id: team_marketing.id

        assert_equal [team_opensource, team_creativity], team_marketing.descendants
        assert_equal [], team_engineering.descendants
        assert_equal [team_employees, team_marketing], team_opensource.ancestors
        assert_equal [team_employees, team_marketing], team_creativity.ancestors

        team_opensource.add_member mike
        team_creativity.add_member jane

        refute_accessible(mike, team_creativity)
        assert_accessible(mike, team_opensource)
        assert_accessible(mike, team_marketing)
        refute_accessible(mike, team_engineering)
        assert_accessible(mike, team_employees)

        assert_accessible(jane, team_creativity)
        refute_accessible(jane, team_opensource)
        assert_accessible(jane, team_marketing)
        refute_accessible(jane, team_engineering)
        assert_accessible(jane, team_employees)

        # And we move marketing to engineering
        #
        #                                      creativity
        #                                     /
        # employees - engineering - marketing
        #                                     \
        #                                       opensource
        #
        team_marketing.parent_team = team_engineering

        refute_accessible(mike, team_creativity)
        assert_accessible(mike, team_opensource)
        assert_accessible(mike, team_engineering)
        assert_accessible(mike, team_employees)
        assert_accessible(mike, team_marketing)

        assert_accessible(jane, team_creativity)
        refute_accessible(jane, team_opensource)
        assert_accessible(jane, team_engineering)
        assert_accessible(jane, team_employees)
        assert_accessible(jane, team_marketing)
      end

      test "moving a root node to another place" do
        aki = create(:user, login: "aki")
        brandon = create(:user, login: "brandon")
        katrina = create(:user, login: "katrina")

        # Now we have this hierarchy: marketing and employees are both roots
        #
        #  marketing - opensource
        #
        #  employees - engineering
        #
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing"
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id

        team_marketing.add_member  aki
        team_marketing.add_member  brandon
        team_opensource.add_member brandon # Yeah, he is a direct member of both teams
        team_opensource.add_member katrina

        refute_accessible(aki, team_opensource)
        assert_accessible(aki, team_marketing)
        refute_accessible(aki, team_employees)
        refute_accessible(aki, team_engineering)

        assert_accessible(brandon, team_opensource)
        assert_accessible(brandon, team_marketing)
        refute_accessible(brandon, team_employees)
        refute_accessible(brandon, team_engineering)

        assert_accessible(katrina, team_opensource)
        assert_accessible(katrina, team_marketing)
        refute_accessible(katrina, team_employees)
        refute_accessible(katrina, team_engineering)

        # And we want to move marketing to employees
        #
        #              marketing - opensource
        #            /
        #  employees
        #            \
        #              engineering
        #
        team_marketing.parent_team = team_employees

        refute_accessible(aki, team_opensource)
        assert_accessible(aki, team_marketing)
        assert_accessible(aki, team_employees)
        refute_accessible(aki, team_engineering)

        assert_accessible(brandon, team_opensource)
        assert_accessible(brandon, team_marketing)
        assert_accessible(brandon, team_employees)
        refute_accessible(brandon, team_engineering)

        assert_accessible(katrina, team_opensource)
        assert_accessible(katrina, team_marketing)
        assert_accessible(katrina, team_employees)
        refute_accessible(katrina, team_engineering)

        assert_equal [0], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_deleted").map(&:value)
        assert_equal [4], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_created").map(&:value)
      end

      test "moving a team to the root of the hierarchy" do
        aki = create(:user, login: "aki")
        brandon = create(:user, login: "brandon")
        katrina = create(:user, login: "katrina")

        # Now we have this hierarchy:
        #
        #              marketing - opensource
        #            /
        #  employees
        #            \
        #              engineering
        #
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id
        team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: team_employees.id
        team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: team_marketing.id

        team_marketing.add_member  aki
        team_marketing.add_member  brandon
        team_opensource.add_member brandon # Yeah, he is a direct member of both teams
        team_opensource.add_member katrina

        # Make marketing a root
        #
        #  marketing - opensource
        #
        #  employees - engineering
        #
        team_marketing.parent_team = nil

        refute_accessible(aki, team_opensource)
        assert_accessible(aki, team_marketing)
        refute_accessible(aki, team_employees)
        refute_accessible(aki, team_engineering)

        assert_accessible(brandon, team_opensource)
        assert_accessible(brandon, team_marketing)
        refute_accessible(brandon, team_employees)
        refute_accessible(brandon, team_engineering)

        assert_accessible(katrina, team_opensource)
        assert_accessible(katrina, team_marketing)
        refute_accessible(katrina, team_employees)
        refute_accessible(katrina, team_engineering)

        assert_equal [4], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_deleted").map(&:value)
        assert_equal [0], GitHub.dogstats.distributions("ability.recalculate_abilities_operation.dist.abilities_created").map(&:value)
      end

      test "recalculation is triggered" do
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing"

        Team::ParentChange::RecalculateAbilitiesOperation.any_instance.expects(:execute).once

        team_employees.parent_team = team_marketing
      end

      test "recalculation is not triggered when creating cycles" do
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: team_employees.id

        Team::ParentChange::RecalculateAbilitiesOperation.any_instance.expects(:execute).never

        team_employees.parent_team = team_marketing
      end

      test "recalculation is not triggered when parent_id doesn't change" do
        team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
        Team::ParentChange::RecalculateAbilitiesOperation.any_instance.expects(:execute).never

        team_employees.name = "People"
        assert team_employees.save
      end
    end
  end
end
