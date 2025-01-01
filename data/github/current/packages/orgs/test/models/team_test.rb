# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/api_programmatic_grant_helpers"

# NOTE: there are many, many more team tests in Organization -- they should be moved over here eventually
class TeamModelTest < GitHub::TestCase
  include TeamSyncTestHelper
  include ApiProgrammaticGrantHelpers
  include HydroTestHelpers
  include FineGrainedPermissionsTestHelper
  fixtures do
    @owner = create :user
    @org = create :organization, plan: "bronze", admin: @owner
    @org.allow_private_repository_forking(actor: @owner)
    @repo = create :private_repository, owner: @org, from_example: :simple
    @github_employees_team = feature_team("Employees")
    @future_employee = create :user
    create :personal_token_oauth_access, user: @future_employee
    create(:public_key, user: @future_employee).verify(@future_employee)

    @org_plus = create :business_plus_organization, admin: @owner
    @repo_plus = create :private_repository, :minimal, owner: @org_plus

    @org_with_teams = create :organization, admin: @owner
    @public_team = create :public_team, organization: @org_with_teams
    @team = create(:team, organization: @org, name: "Foo bar", slug: "foo-bar")
    @collabs_team = create :team, organization: @org, name: "collaborators"
    @closed_team = create :team, organization: @org, privacy: :closed
    @closed_child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @closed_team.id)
    @parent_team = create(:team, organization: @org, privacy: :closed)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @parent_team.id)

    @other_owner = create :user
    @other_org = create :organization, plan: "bronze", admin: @other_owner

    @user = create(:user)
    @another_user = create(:user)
    @member = create(:user)
    @other_member = create :user
    @child_team_member = create :user
    @team_maintainer = create :user

    @project = create :project, owner: @org
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  def setup_enterprise_team
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    @emu_admin = create :emu, :owner
    @emu = @emu_admin.enterprise_managed_business
    @enterprise_team = create :enterprise_team, business: @emu
    @emu_org = create :organization, business: @emu
    @emu_org.add_member(@emu_admin)
    @emu_team = create :public_team, organization: @emu_org
    @enterprise_team_org_mapping = EnterpriseTeamOrganizationMapping.create!(enterprise_team: @enterprise_team, organization: @emu_org, team: @emu_team)
  end

  test "Team.none matches nothing" do
    team = create :team, organization: @org

    assert_includes Team.all, team
    refute_includes Team.none, team
  end

  test "#name_with_owner uses team's slug rather than name" do
    assert_equal "#{@org}/foo-bar", @team.name_with_owner
  end

  test "#permalink generates the right url" do
    assert_equal "/orgs/#{@org}/teams/#{@team.slug}", @team.permalink(include_host: false)
  end

  context "#cant_change_visibility?" do
    test "returns true if team has child teams" do
      assert_equal true, @closed_team.cant_change_visibility?
    end

    test "returns true if team is enterprise managed" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      et = create :enterprise_team
      EnterpriseTeamOrganizationMapping.create(organization: @org, team: @closed_team, enterprise_team: et)

      assert_equal true, @closed_team.cant_change_visibility?
    end unless GitHub.single_business_environment?

    test "returns false if team has no child teams and is not enterprise managed" do
      assert_equal false, @team.cant_change_visibility?
    end
  end

  context "#add_member" do

    test "successfully adds org member to team" do
      @org.add_member(@user)

      result = @team.add_member(@user, adder: @org.admin)
      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "successfully adds org member to team without adder specified" do
      @org.add_member(@user)

      result = @team.add_member(@user)
      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "returns NOT_USER if nil is passed as user arg" do
      result = @team.add_member(nil)
      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    if GitHub.user_abuse_mitigation_enabled?
      test "does not add member if invitee is blocked by adder" do
        @org.add_member(@user)
        assert @user.block(@org.admin)

        result = @team.add_member(@user, adder: @org.admin)
        refute_predicate result, :success?
        assert_equal Team::AddMemberStatus::BLOCKED, result
        refute @team.member?(@user)
      end
    end

    if GitHub.bypass_org_invites_enabled?
      test "returns NO_PERMISSION if user cannot add member" do
        result = @team.add_member(@user, adder: @member)
        refute_predicate result, :success?
        assert_equal Team::AddMemberStatus::NO_PERMISSION, result
      end
    end

    test "returns TRADE_CONTROLS_RESTRICTED if org is fully trade controls restricted" do
      @org.trade_controls_restriction.full!
      @team.reload

      result = @team.add_member(@user, adder: @owner)
      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::TRADE_CONTROLS_RESTRICTED, result
    end

    test "works if org is partial trade controls restricted" do
      @org.trade_controls_restriction.partial!
      @team.reload

      result = @team.add_member(@user, adder: @org.admin)
      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "instruments membership event to hydro", skip_enterprise: true do
      @org.add_member(@user)

      GitHub.hydro_publisher.sink&.messages&.clear

      @team.add_member(@user)
      assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
    end

    test "enqueues an email to notify a user when they're added to a team" do
      @org.add_member(@user)
      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)

      assert_difference "ActionMailer::Base.deliveries.size", 1 do
        assert_performed_with(job: ApplicationDeliveryJob, queue: "team_member_added_emails") do
          @team.add_member(@user)
        end
      end
    end

    test "does not send an email to users users when they're added to a team with send_notification false" do
      @org.add_member(@user)
      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)

      assert_no_performed_jobs(only: ApplicationDeliveryJob) do
        @team.add_member(@user, { send_notification: false })
      end
    end

    test "does not send an email to suspended users when they're added to a team" do
      @org.add_member(@user)
      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)
      @user.suspend("reason")

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @team.add_member(@user)
      end
    end

    test "allows member to be added even if organization appears to be out of seats (which can happen when using a read-only DB connection inside of a transaction adding the user to the organization)" do
      organization = create(:business_plus_organization, seats: 1) # single seat occupied by the admin
      team = create :team, organization: organization

      result = team.add_member(@user, skip_organization_seat_checks: true)

      assert_equal Team::AddMemberStatus::SUCCESS, result
      assert_includes organization.member_ids, @user.id
      assert_includes team.member_ids, @user.id
    end

    test "does not allow a member to be added if organization does not have sufficient seats available" do
      organization = create(:business_plus_organization, seats: 1) # single seat occupied by the admin
      team = create :team, organization: organization

      result = team.add_member(@user)

      assert_equal Team::AddMemberStatus::NO_SEAT, result
      refute_includes organization.member_ids, @user.id
      refute_includes team.member_ids, @user.id
    end
  end

  context "#add_member_bulk" do
    test "returns TRADE_CONTROLS_RESTRICTED if org is fully trade controls restricted" do
      @org.trade_controls_restriction.full!
      @team.reload

      result = @team.bulk_add_members([@user], adder: @owner)

      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::TRADE_CONTROLS_RESTRICTED, result
    end

    test "works if org is partial trade controls restricted" do
      @org.trade_controls_restriction.partial!
      @team.reload

      result = @team.bulk_add_members([@user], adder: @org.admin)

      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "returns NOT_USER if an empty array" do
      result = @team.bulk_add_members([])
      refute_predicate result, :success?
      refute_predicate result, :should_failover?
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    test "returns NOT_AN_ARRAY if nil is passed as users arg" do
      result = @team.bulk_add_members(nil)
      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::NOT_AN_ARRAY, result
    end

    test "returns NOT_USER if an array with a single nil is" do
      result = @team.bulk_add_members([nil])
      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    test "returns SUCCESS if nil is passed as one of users args" do
      result = @team.bulk_add_members([@user, nil])
      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "does not auto subscribe users if called with :enterprise_team" do
      Team.any_instance.expects(:auto_subscribe_user).never
      result = @team.bulk_add_members([@user], caller_type: :enterprise_team)
    end

    test "returns NOT_USER if organization is passed as one of users args" do
      result = @team.bulk_add_members([@user, @org])
      refute_predicate result, :success?
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    test "instruments membership events to hydro", skip_enterprise: true do
      @org.bulk_add_members([@user, @another_user])

      GitHub.hydro_publisher.sink&.messages&.clear

      @team.bulk_add_members([@user, @another_user])
      assert_hydro_messages(count: 2, schema: "github.v1.MembershipUpdate")
    end

    test "enqueues an email to notify users when they're added to a team" do
      @org.bulk_add_members([@user, @another_user])

      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)

      assert_difference "ActionMailer::Base.deliveries.size", 2 do
        assert_performed_with(job: ApplicationDeliveryJob, queue: "team_member_added_emails") do
          @team.bulk_add_members([@user, @another_user])
        end
      end
    end

    test "does not send an email to users when they're added to a team with send_notification false" do
      @org.bulk_add_members([@user, @another_user])
      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)

      assert_no_performed_jobs(only: ApplicationDeliveryJob) do
        @team.bulk_add_members([@user, @another_user], { send_notification: false })
      end
    end

    test "does not send an email to suspended users when they're added to a team" do
      @org.bulk_add_members([@user, @another_user])
      repo = create :repository, owner: @org
      @team.add_repository_directly(repo)
      @user.suspend("reason")

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @team.bulk_add_members([@user, @another_user])
      end
    end

    test "allows members to be added even if organization appears to be out of seats (which can happen when using a read-only DB connection inside of a transaction adding the user to the organization)" do
      organization = create(:business_plus_organization, seats: 1) # single seat occupied by the admin
      team = create :team, organization: organization

      result = team.bulk_add_members([@user, @another_user], skip_organization_seat_checks: true)

      assert_equal Team::AddMemberStatus::SUCCESS, result
      assert_includes organization.member_ids, @user.id
      assert_includes team.member_ids, @user.id
      assert_includes organization.member_ids, @another_user.id
      assert_includes team.member_ids, @another_user.id
    end

    test "does not allow members to be added if organization does not have sufficient seats available" do
      organization = create(:business_plus_organization, seats: 1) # single seat occupied by the admin
      team = create :team, organization: organization

      result = team.bulk_add_members([@user, @another_user])

      assert_equal Team::AddMemberStatus::NO_SEAT, result
      refute_includes organization.member_ids, @user.id
      refute_includes team.member_ids, @user.id
      refute_includes organization.member_ids, @another_user.id
      refute_includes team.member_ids, @another_user.id
    end

    test "successfully adds org member to team" do
      @org.add_member(@user)

      result = @team.bulk_add_members([@user], adder: @org.admin)
      assert_predicate result, :success?
      assert_equal Team::AddMemberStatus::SUCCESS, result
      assert_equal @team.members, [@user]
    end

    test "successfully adds multiple org members to team" do
      @org.add_member(@user)
      @org.add_member(@another_user)

      result = @team.bulk_add_members([@user, @another_user], adder: @org.admin)
      assert_predicate result, :success?
      assert_same_elements @team.members, [@user, @another_user]
      assert @org.member?(@another_user)
    end

    test "raises ActiveRecord::RecordNotFound error when team is destroyed" do
      refute @org.member?(@user)
      refute @team.member?(@user)

      @team.destroy

      assert_raises ActiveRecord::RecordNotFound do
        @team.bulk_add_members([@user], adder: @org.admin)
      end

      # Abilities are not removed
      assert @org.member?(@user)
      assert @team.member?(@user)
    end

    test "retries successfully DashboardNoticesStore.bulk_add on ActiveRecord::Deadlocked" do
      GitHub.flipper[:team_bulk_add_dashboard_deadlock_retry].enable
      @org.add_member(@user)

      DashboardNoticesStore.stubs(:bulk_add).raises(ActiveRecord::Deadlocked).then.returns(GitHub::Result.new)

      result = @team.bulk_add_members([@user], adder: @org.admin)
      assert_predicate result, :success?
    end

    test "raises error DashboardNoticesStore.bulk_add on ActiveRecord::Deadlocked when ff disabled" do
      GitHub.flipper[:team_bulk_add_dashboard_deadlock_retry].disable
      @org.add_member(@user)

      DashboardNoticesStore.stubs(:bulk_add).raises(ActiveRecord::Deadlocked).then.returns(true)

      assert_raises ActiveRecord::Deadlocked do
        @team.bulk_add_members([@user], adder: @org.admin)
      end
    end
  end

  # TODO: Duplicate these tests for GHEC environments with `bulk_remove_members` when we support GHEC ESM
  context "#remove_member" do
    test "instruments membership event to hydro", skip_enterprise: true do
      @org.add_member(@user)
      @team.add_member(@user)

      GitHub.hydro_publisher.sink&.messages&.clear

      @team.remove_member(@user)
      assert_hydro_messages(count: 1, schema: "github.v1.MembershipUpdate")
    end

    test "allows changes to an enterprise managed team by the enterprise team", skip_enterprise: true do
      setup_enterprise_team
      @emu_team.add_member(@emu_admin, caller_type: :enterprise_team)
      assert_equal [@emu_admin.id], @emu_team.member_ids
      @emu_team.remove_member(@emu_admin, caller_type: :enterprise_team)
      assert_empty @emu_team.member_ids
    end

    test "does not allow changes to an enterprise managed team by anything else", skip_enterprise: true do
      setup_enterprise_team
      @emu_team.add_member(@emu_admin, caller_type: :enterprise_team)
      assert_equal [@emu_admin.id], @emu_team.member_ids
      @emu_team.remove_member(@emu_admin)
      assert_equal [@emu_admin.id], @emu_team.member_ids
    end
  end

  context "new github hires" do
    if GitHub.enterprise?
      test "access is not revoked when added to employees team on enterprise" do
        assert_equal 1, @future_employee.public_keys.to_a.count(&:verified?)
        assert_equal 1, @future_employee.oauth_accesses.length

        @github_employees_team.add_member(@future_employee)

        assert_equal 1, @future_employee.public_keys.to_a.count(&:verified?)
        assert_equal 1, @future_employee.oauth_accesses.length
      end
    else
      test "access is revoked when added to employees team on dotcom" do
        assert_equal 1, @future_employee.public_keys.to_a.count(&:verified?)
        assert_equal 1, @future_employee.oauth_accesses.length

        perform_enqueued_jobs(only: [RemoveOauthUserTokensJob]) do
          @github_employees_team.add_member(@future_employee)
        end

        @future_employee.reload

        assert_equal 0, @future_employee.public_keys.to_a.count(&:verified?)
        assert_equal 0, @future_employee.oauth_accesses.length
      end
    end

    test "access is not revoked when added to other teams" do
      assert_equal 1, @future_employee.public_keys.to_a.count(&:verified?)
      assert_equal 1, @future_employee.oauth_accesses.length

      @team.add_member(@future_employee)

      assert_equal 1, @future_employee.public_keys.to_a.count(&:verified?)
      assert_equal 1, @future_employee.oauth_accesses.length
    end
  end

  context "team names" do
    test "strips leading & trailing whitespace from team names" do
      team = create(:team, organization: @org, name: "  spaces  ")
      assert_equal team.name, "spaces"
    end

    test "names are unique, including non-deleted" do
      team = build(:team, organization: @org_with_teams, name: @org_with_teams.teams.first.name)
      refute team.save
      assert_equal 1, team.errors.full_messages.size
      assert_match(/must be unique for this org/, team.errors.full_messages.first)
    end

    test "names are unique, excluding deleted" do
      create(:team, organization: @org, name: "existing", deleted: true)
      assert build(:team, organization: @org, name: "existing").save
    end
  end

  context "slug generation" do
    test "sets a slug if it is nil (for 'legacy' teams)'" do
      team = create(:team, organization: @org, name: "Pillow fighters")
      team.slug = nil
      team.save(validate: false)
      team.reload
      assert_nil team.slug
      team.save!
      assert_equal "pillow-fighters", team.slug
    end

    test "happens on create" do
      team = create(:team, organization: @org, name: "Pillow fighters")
      assert_equal "pillow-fighters", team.slug
    end

    test "crazy unicode stuff" do
      team = create(:team, organization: @org, name: "designers™")
      assert_equal "designers", team.slug
    end

    test "does not care about duplicates between different orgs" do
      @org2 = create :organization
      team_from_different_org = create(:team, name: "designers", organization: @org2)
      team = create(:team, organization: @org, name: "designers")
      assert_equal "designers", team_from_different_org.slug
      assert_equal "designers", team.slug
    end

    test "avoids duplicates within the org" do
      team1 = create(:team, organization: @org, name: "designers on droogs")
      team2 = create(:team, organization: @org, name: "designers on-droogs")
      team3 = create(:team, organization: @org, name: "designers-on droogs")
      assert_equal "designers-on-droogs", team1.slug
      assert_equal "designers-on-droogs-1", team2.slug
      assert_equal "designers-on-droogs-2", team3.slug
    end

    test "does not do anything if the name has not changed" do
      team = create(:team, organization: @org, name: "designers")
      team.reload
      team.expects(:generate_unique_slug).never
      team.save!
    end

    test "regenerates the slug when the name changes" do
      team = create(:team, organization: @org, name: "designers")
      team.name = "graphical fairy peoples - vice squad"
      team.save!
      assert_equal "graphical-fairy-peoples-vice-squad", team.slug
    end

    test "does not change the slug if the team name is lowercased (with no other changes)" do
      team = create(:team, organization: @org, name: "DotCom")
      assert_equal "dotcom", team.slug
      team.name = "dotcom"
      team.save!
      assert_equal "dotcom", team.slug
    end

    test "periods get stripped from slugs" do
      team = create(:team, organization: @org, name: ".com")
      assert_equal ".com", team.name
      assert_equal "com", team.slug
    end

    test "leading/trailing spaces get stripped from slug" do
      team = create(:team, organization: @org, name: "  has spaces ")
      assert_equal team.slug, "has-spaces"
    end

    test "generates nice fake slugs when the team name is all unicode" do
      team = create(:team, organization: @org, name: "£")
      assert_equal "team", team.slug

      team = create(:team, organization: @org, name: "¢")
      assert_equal "team-1", team.slug
    end
  end

  context "finding by org and team name" do
    test "finds a team" do
      assert_equal @github_employees_team,
        Team.with_org_name_and_slug("github", "Employees")
    end
  end

  context "finding by combined slug name" do
    test "works with a full combined slug" do
      assert_equal @team, Team.find_by_combined_slug(@team.combined_slug)
    end

    test "fails for fake slugs" do
      assert_nil Team.find_by_combined_slug("def/unkt")
    end

    test "raises for malformed slugs" do
      assert_raises ArgumentError do
        Team.find_by_combined_slug("defunkt")
      end
    end
  end

  context "#permalink" do
    test "without include_host includes domain" do
      org   = create :organization, login: "apple"
      team  = create :team, organization: org, name: "developers"

      assert_equal "https://github.com/orgs/apple/teams/developers", team.permalink
    end

    test "with include_host true includes domain" do
      org   = create :organization, login: "apple"
      team  = create :team, organization: org, name: "developers"

      assert_equal "https://github.com/orgs/apple/teams/developers", team.permalink(include_host: true)
    end

    test "with include_host false omits domain" do
      org   = create :organization, login: "apple"
      team  = create :team, organization: org, name: "developers"

      assert_equal "/orgs/apple/teams/developers", team.permalink(include_host: false)
    end
  end

  context "creator" do
    test "it defaults to the organization when blank" do
      assert_equal @org, @team.creator

      # Make sure it still works the default way
      @team.creator = @user
      assert_equal @user, @team.creator
    end
  end

  context "#destroy" do
    test "updates deleted field" do
      @team.destroy
      assert @team.deleted
    end

    test "invokes DestroyOperation" do
      operation_stub = Team::Destruction::DestroyOperation.new(@team)
      operation_stub.expects(:execute).once
      Team::Destruction::DestroyOperation.expects(:new).with(@team).returns(operation_stub)
      @team.destroy
    end

    test "removes notification subscriptions" do
      @team.add_member(@user)
      assert GitHub.newsies.subscription_status(@user, @team).valid?

      only = [DestroyTeamDependantsJob, Newsies::DeleteAllForListJob]
      perform_enqueued_jobs(only: only) { @team.destroy }

      refute GitHub.newsies.subscription_status(@user, @team).valid?
    end
  end

  context "team membership" do
    test "team knows about members" do
      assert !@team.member?(@user), "is a member"
      @team.add_member @user
      assert @team.member?(@user), "not a member"
      assert !@team.member?(@org.admins.first), "owner is a member"
    end
  end

  context "sending team added email" do
    test "does not send email when adding yourself" do
      repo = create :repository, owner: @org
      @team.add_repository repo, :pull
      assert_no_difference "ActionMailer::Base.deliveries.size" do
        @team.add_member @org.admins.first, adder: @org.admins.first
      end
    end

    test "a new team has no members" do
      team = build :team, organization: @org
      assert_equal [], team.members
      assert_equal [], team.member_ids
    end
  end

  test "organization members cannot view secret organization teams" do
    team = create(:team, organization: @org, privacy: :secret)
    @org.add_member @user
    refute_able @user, :read, team
  end

  test "organization members can view closed organization teams" do
    @org.add_member @user
    assert_able @user, :read, @closed_team
  end

  test "knows whether someone can leave" do
    owners_team = @org.legacy_owners_team

    refute @team.leavable_by?(@user), "Can't leave a normal team when they're not a member"

    @team.add_member @user
    assert @team.leavable_by?(@user), "Can leave a normal team when they're a member"
  end

  context "can_add_repositories?" do
    test "true for a user with admin on a regular team" do
      assert @team.can_add_repositories?(@owner)
    end

    test "false for a non-admin user" do
      @team.add_member(@user)

      refute @team.can_add_repositories?(@user)
    end
  end

  test "teams names are case insensitive" do
    team1 = create :team, organization: @org, name: "NewTeam"
    team2 = @org.teams.new name: "newteam"

    assert team1.valid?
    assert !team2.valid?, "team2 should not be valid"
    assert team2.errors[:name], "name should not be valid"
  end

  test "long team names are rejected" do
    team1 = build :team, organization: @org, name: "a" * 256
    refute team1.valid?, "team name should be no more than 255 characters"
    assert team1.errors[:name].any?
  end

  test "team permissions are validated" do
    team = @org.teams.build name: "new team"
    team.permission = "nope"
    refute team.valid?
    assert team.errors[:permission]
  end

  context "retrieving repositories" do
    test "returns an empty list when no repos present" do
      assert_equal [], @collabs_team.batched_repositories
    end

    test "returns the repos added to the team" do
      repo1 = create :repository, owner: @org
      repo2 = create :repository, owner: @org
      repo3 = create :repository, owner: @org

      @collabs_team.add_repository repo1, :pull
      @collabs_team.add_repository repo2, :pull
      assert_equal [repo1, repo2], @collabs_team.batched_repositories
    end
  end

  context "adding and removing a repository" do
    context "without direct org membership" do
      test "#add_repository adds a repository to a normal team" do
        @collabs_team.add_repository @repo, :pull
        assert @collabs_team.batched_repositories.include? @repo
      end

      test "#add_repository grants read to teams with pull permission" do
        team = create :team, organization: @org, permission: "pull"
        team.add_repository @repo, :pull
        assert_able team, :read, @repo
        refute_able team, :write, @repo
      end

      test "#add_repository grants write to teams with push permission" do
        team = create :team, organization: @org, permission: "push"
        team.add_repository @repo, :push
        assert_able team, :write, @repo
        refute_able team, :admin, @repo
      end

      test "#add_repository grants admin to teams with admin permission" do
        team = create :team, organization: @org, permission: "admin"
        team.add_repository @repo, :admin
        assert_able team, :admin, @repo
      end

      test "#add_repository grants maintain permission" do
        team = create :team, organization: @org_plus, permission: "pull"
        team.add_repository @repo_plus, :maintain
        assert_equal :maintain, @repo_plus.direct_role_for(team)
      end

      test "#add_repository grants triage permission" do
        team = create :team, organization: @org_plus, permission: "pull"
        team.add_repository @repo_plus, :triage
        assert_equal :triage, @repo_plus.direct_role_for(team)
      end

      test "#adding then updating still grants correct permission" do
        team = create :team, organization: @org_plus, permission: "pull"
        team.add_repository @repo_plus, :push
        team.update_repository_permission @repo_plus, :pull
        assert_equal :read, @repo_plus.direct_role_for(team)
      end

      test "#add_repository subscribes the team to a repo if the team is push or admin" do
        users = Array.new(4).map do
          user = create :user
          GitHub.newsies.get_and_update_settings(user) do |settings|
            settings.auto_subscribe_repositories = true
          end
          user
        end
        team = create :team, organization: @org, permission: "push"
        team.add_member users[0]
        team.add_member users[1]

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", team.members.size) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
            team.add_repository @repo, :push
          end
        end

        team = create :team, organization: @org, permission: "admin"
        team.add_member users[2]
        team.add_member users[3]

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", team.members.size) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
            team.add_repository @repo, :admin
          end
        end
      end

      test "#add_repository doesn't subscribe team to a repo if the team is pull" do
        users = Array.new(2).map do
          user = create :user
          GitHub.newsies.get_and_update_settings(user) do |settings|
            settings.auto_subscribe_repositories = true
          end
          user
        end
        team = create :team, organization: @org, permission: "pull"
        team.add_member users[0]
        team.add_member users[1]
        GitHub.newsies.expects(:async_subscribe_users_to_repository).never
        assert_no_difference "GitHub.newsies.subscribers(@repo).size" do
          only = [DeliverHookEventJob, TeamAddForksJob]
          perform_enqueued_jobs(only: only) do
            team.add_repository @repo, :pull
          end
        end
      end

      test "#add_repository allows you set a different owner" do
        new_org = create :organization
        new_team = create :team, organization: new_org
        new_team.add_repository @repo, :pull, allow_different_owner: true
        assert new_team.batched_repositories.include? @repo
      end

      test "#add_repository does not allow an org-owned fork on a plan-owned team" do
        org = create :organization
        org.allow_private_repository_forking(actor: org.admins.first)
        repo = create :private_repository, owner: org, from_example: :simple
        team = create :team, organization: org
        forking_org = create :organization
        forking_org.add_admin(org.admins.first)
        org_fork, status = repo.fork(forker: org.admins.first, org: forking_org)
        assert_equal :created, status

        assert team.add_repository(org_fork, :pull).error?
      end

      test "#remove removes a repository from a normal team" do
        @collabs_team.add_repository @repo, :pull
        @collabs_team.remove_repository @repo
        assert_equal [], @collabs_team.batched_repositories
      end

      test "#remove_repository deletes private forks of sub-team members without access" do
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }

        user1 = create :user
        @closed_team.add_member(user1)
        refute @repo.pullable_by?(user1)
        @closed_team.add_repository(@repo, :pull)
        team2 = create :team, organization: @org, privacy: :closed, parent_team_id: @closed_team.id
        user2 = create :user
        team2.add_member(user2)
        team3 = create :team, organization: @org, privacy: :closed, parent_team_id: team2.id
        user3 = create :user
        team3.add_member(user3)

        user1_fork, status = @repo.fork(forker: user1)
        assert user1_fork, "Fork should have succeeded but failed with status '#{status}'"
        user2_fork, status = @repo.fork(forker: user2)
        assert user2_fork, "Fork should have succeeded but failed with status '#{status}'"
        user3_fork, status = @repo.fork(forker: user3)
        assert user3_fork, "Fork should have succeeded but failed with status '#{status}'"

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @closed_team.remove_repository(@repo) }

        assert Repositories::Public.is_deleted?(user1_fork.id), "Private fork should be deleted"
        assert Repositories::Public.is_deleted?(user2_fork.id), "Private fork should be deleted"
        assert Repositories::Public.is_deleted?(user3_fork.id), "Private fork should be deleted"
      end

      test "#remove_repository leaves private forks of sub-team members with explicit access" do
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }

        user1 = create :user
        @closed_team.add_member(user1)
        refute @repo.pullable_by?(user1)
        @closed_team.add_repository(@repo, :pull)
        team2 = create :team, organization: @org, privacy: :closed, parent_team_id: @closed_team.id
        user2 = create :user
        team2.add_member(user2)
        team2.add_repository(@repo, :pull)
        team3 = create :team, organization: @org, privacy: :closed, parent_team_id: team2.id
        user3 = create :user
        team3.add_member(user3)
        team3.add_repository(@repo, :pull)

        user1_fork, status = @repo.fork(forker: user1)
        assert user1_fork, "Fork should have succeeded but failed with status '#{status}'"
        user2_fork, status = @repo.fork(forker: user2)
        assert user2_fork, "Fork should have succeeded but failed with status '#{status}'"
        user3_fork, status = @repo.fork(forker: user3)
        assert user3_fork, "Fork should have succeeded but failed with status '#{status}'"

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @closed_team.remove_repository(@repo) }

        assert Repositories::Public.is_deleted?(user1_fork.id), "Private fork should be deleted"
        assert Repositories::Public.is_active?(user2_fork.id), "Team 2 private fork should not be removed"
        assert Repositories::Public.is_active?(user3_fork.id), "Team 3 private fork should not be removed"
      end

      test "#remove_repository deletes forks of forks of team members without access" do
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }

        user1 = create :user
        @closed_team.add_member(user1)
        user2 = create :user
        @closed_team.add_member(user2)
        @closed_team.add_repository(@repo, :pull)

        user1_fork, status = @repo.fork(forker: user1)
        assert user1_fork, "Fork should have succeeded but failed with status '#{status}'"
        user1_fork.add_member(user2)

        user2_fork, status = user1_fork.fork(forker: user2)
        assert user2_fork, "Fork should have succeeded but failed with status '#{status}'"

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @closed_team.remove_repository(@repo) }

        assert Repositories::Public.is_deleted?(user1_fork.id), "Private fork should be deleted"
        assert Repositories::Public.is_deleted?(user2_fork.id), "Private fork should be deleted"
      end

      test "#remove_repository deletes forks of forks of collaborators without access" do
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }

        user1 = create :user
        @closed_team.add_member(user1)
        @closed_team.add_repository(@repo, :pull)
        user2 = create :user
        refute @repo.pullable_by?(user2)

        user1_fork, status = @repo.fork(forker: user1)
        assert user1_fork, "Fork should have succeeded but failed with status '#{status}'"
        user1_fork.add_member(user2)
        user2_fork, status = user1_fork.fork(forker: user2)
        assert user2_fork, "Fork should have succeeded but failed with status '#{status}'"

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @closed_team.remove_repository(@repo) }

        assert Repositories::Public.is_deleted?(user1_fork.id), "Private fork should be deleted"
        assert Repositories::Public.is_deleted?(user2_fork.id), "Private fork should be deleted"
      end

      test "#remove_repository does not delete nested fork when there's access to new parent" do
        perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:none, actor: @owner) }

        user1 = create :user
        @closed_team.add_member(user1)
        @closed_team.add_repository(@repo, :pull)
        user2 = create :user
        refute @repo.pullable_by?(user2)
        user3 = create :user
        @repo.add_member(user3)
        assert @repo.pullable_by?(user3)

        user1_fork, status = @repo.fork(forker: user1)
        assert user1_fork, "Fork should have succeeded but failed with status '#{status}'"
        user1_fork.add_member(user2)

        user2_fork, status = user1_fork.fork(forker: user2)
        assert user2_fork, "Fork should have succeeded but failed with status '#{status}'"
        user2_fork.add_member(user3)
        user3_fork, status = user2_fork.fork(forker: user3)
        assert user3_fork, "Fork should have succeeded but failed with status '#{status}'"

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @closed_team.remove_repository(@repo) }

        assert Repositories::Public.is_deleted?(user1_fork.id), "Private fork should be deleted"

        assert Repositories::Public.is_deleted?(user2_fork.id), "Private fork should be deleted"
        assert_equal @repo, user3_fork.reload.parent
        assert Repositories::Public.is_active?(user3_fork.id), "Private fork should not be removed"
      end
    end

    context "repo group settings" do
      test "#add_repository blocked by group setting" do
        group = @repo.join_group("foo")
        access = AccessGroupSetting.add(@repo.owner, group.group_path)

        red_team = create(:team, organization: @org, name: "red team")
        blue_team = create(:team, organization: @org, name: "blue team")

        # verify that add/remove works fine when group setting is not defined
        red_team.add_repository(@repo, "read")
        assert_able red_team, :read, @repo

        # lock down the repo
        access.deny_team_changes
        access.add("write", blue_team.id)
        access.save!

        # add the blue team by bypassing the group setting check
        @repo.add_team(blue_team, action: :read)
        assert_able blue_team, :read, @repo

        # should be able to remove a team not part of access settings
        red_team.remove_repository(@repo)
        refute_able red_team, :read, @repo

        # should not be able to remove blue team
        blue_team.remove_repository(@repo)
        assert_able blue_team, :read, @repo

        # should not be able to add red team
        result = red_team.add_repository(@repo, "read")
        assert_equal Team::ModifyRepositoryStatus::GROUP_SETTINGS, result
        refute_able red_team, :read, @repo

        access.allow_team_changes
        access.save!

        result = red_team.add_repository(@repo, "read")
        assert_equal Team::ModifyRepositoryStatus::SUCCESS, result
        assert_able red_team, :read, @repo
      end

      test "change permissions" do
        group = @repo.join_group("foo")
        access = AccessGroupSetting.add(@repo.owner, group.group_path)

        blue_team = create(:team, organization: @org, name: "blue team")

        # verify that update permissions works when no settings are defined
        blue_team.add_repository(@repo, "read")
        blue_team.update_repository_permission(@repo, :write)
        assert_able blue_team, :write, @repo

        # lock down the repo
        access.deny_team_changes
        access.add("write", blue_team.id)
        access.save!

        # should fail because deny_team_changes is set
        blue_team.update_repository_permission(@repo, :admin)
        refute_able blue_team, :admin, @repo
        assert_able blue_team, :write, @repo

        access.allow_team_changes
        access.save!

        # should fail because it's less privilege
        blue_team.update_repository_permission(@repo, :triage)
        assert_able blue_team, :write, @repo
        refute_able blue_team, :admin, @repo

        # should succeed because it's more privilege
        blue_team.update_repository_permission(@repo, :admin)
        assert_able blue_team, :admin, @repo
        assert_able blue_team, :write, @repo
      end
    end if GitHub.flipper[:repos_group].enabled?

    context "with direct org membership enabled" do
      test "#add_repository with invalid permission returns an error response" do
        assert_equal Team::ModifyRepositoryStatus::NO_PERMISSION, @collabs_team.add_repository(@repo, "poke")
        refute @collabs_team.batched_repositories.include? @repo
      end

      test "#add_repository with pull grants read to team" do
        @team.add_repository @repo, :pull
        assert_able @team, :read, @repo
        refute_able @team, :write, @repo
      end

      test "#add_repository with push grants write to team" do
        @team.add_repository @repo, :push
        assert_able @team, :write, @repo
        refute_able @team, :admin, @repo
      end

      test "#add_repository with admin grants admin to team" do
        @team.add_repository @repo, :admin
        assert_able @team, :admin, @repo
      end

      test "#add_repository with perm grants perm to team, regardless of team permission" do
        team = create :team, organization: @org, permission: "push"
        team.add_repository @repo, :pull
        assert_able team, :read, @repo
        refute_able team, :write, @repo
      end

      test "#add_repository subscribes the team to a repo if the team has push or admin on the repo" do
        users = Array.new(5).map do
          user = create :user
          GitHub.newsies.get_and_update_settings(user) do |settings|
            settings.auto_subscribe_repositories = true
          end
          user
        end
        @team.add_repository @repo, "push"
        @team.add_member users[0]

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", 1) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
            @team.add_member users[1]
          end
        end

        team = create :team, organization: @org
        team.add_repository @repo, "admin"
        team.add_member users[2]
        team.add_member users[3]

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", 1) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
            team.add_member users[4]
          end
        end
      end

      test "#add_repository for advisory workspace returns an error response" do
        advisory = create :repository_advisory, :with_workspace, repository: @repo
        assert_equal Team::ModifyRepositoryStatus::ADVISORY_WORKSPACE, @team.add_repository(advisory.workspace_repository, :write)
        refute @team.batched_repositories.include? advisory.workspace_repository
      end

      test "#update repository_permission to existing permission returns dupe status" do
        @team.add_repository @repo, :admin

        resp, queries = log_queries { @team.update_repository_permission @repo, :admin }

        assert_equal Team::ModifyRepositoryStatus::DUPE, resp
        refute queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
      end

      test "#update repository_permission for existing advisory workspace permission returns an error response" do
        advisory = create :repository_advisory, :with_workspace, repository: @repo
        advisory.add_collaborator(@team)

        resp, queries = log_queries { @team.update_repository_permission advisory.workspace_repository, :admin }

        assert_equal Team::ModifyRepositoryStatus::ADVISORY_WORKSPACE, resp
        refute queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
      end

      context "actions in permission format" do
        test "#update_repository_permission with admin grants admin to team" do
          @team.add_repository @repo, :pull

          @team.update_repository_permission @repo, :admin
          assert_able @team, :admin, @repo
        end

        test "#update_repository_permission with maintain grants maintain to team" do
          @team_plus = create :team, organization: @org_plus
          @team_plus.add_repository @repo_plus, :admin
          @team_plus.update_repository_permission @repo_plus, :maintain
          assert Ability.can?(@team_plus, :write, @repo_plus)
          assert UserRole.find_by(role: Role.maintain_role, actor: @team_plus, target: @repo_plus).present?
          refute Ability.can?(@team_plus, :admin, @repo_plus)
          refute_able @team_plus, :admin, @repo_plus
        end

        test "#update_repository_permission with push grants write to team" do
          @team.add_repository @repo, :admin

          @team.update_repository_permission @repo, :push
          assert_able @team, :write, @repo
          refute_able @team, :admin, @repo
        end

        test "#update_repository_permission with triage grants triage to team" do
          @team_plus = create :team, organization: @org_plus
          @team_plus.add_repository @repo_plus, :admin
          @team_plus.update_repository_permission @repo_plus, :triage
          assert Ability.can?(@team_plus, :read, @repo_plus)
          assert UserRole.find_by(role: Role.triage_role, actor: @team_plus, target: @repo_plus).present?
          refute Ability.can?(@team_plus, :admin, @repo_plus)
          refute_able @team_plus, :admin, @repo_plus
        end

        test "#update_repository_permission with pull grants read to team" do
          @team.add_repository @repo, :push

          @team.update_repository_permission @repo, :pull
          assert_able @team, :read, @repo
          refute_able @team, :write, @repo
        end
      end

      context "actions in ability format" do
        test "#update_repository_permission with write grants write to team" do
          @team.add_repository @repo, :admin

          @team.update_repository_permission @repo, :write
          assert_able @team, :write, @repo
          refute_able @team, :admin, @repo
        end

        test "#update_repository_permission with read grants read to team" do
          @team.add_repository @repo, :write

          @team.update_repository_permission @repo, :read
          assert_able @team, :read, @repo
          refute_able @team, :write, @repo
        end
      end

      context "nested team permission changes" do
        test "success status for child team targeting parent team's permission" do
          @closed_team.add_repository(@repo, :push)
          @closed_child_team.add_repository(@repo, :pull)

          assert_equal "push", @closed_team.permission_for(@repo)
          assert_equal "pull", @closed_child_team.permission_for(@repo)

          resp, queries = log_queries { @closed_child_team.update_repository_permission @repo, :push }

          assert_equal Team::ModifyRepositoryStatus::SUCCESS, resp
          assert queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
          assert_equal "push", @closed_child_team.permission_for(@repo)
        end

        test "dupe status for child team targeting its current permission" do
          @closed_team.add_repository(@repo, :push)
          @closed_child_team.add_repository(@repo, :pull)

          assert_equal "push", @closed_team.permission_for(@repo)
          assert_equal "pull", @closed_child_team.permission_for(@repo)

          resp, queries = log_queries { @closed_child_team.update_repository_permission @repo, :pull }

          assert_equal Team::ModifyRepositoryStatus::DUPE, resp
          refute queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
          assert_equal "pull", @closed_child_team.permission_for(@repo)
        end

        test "adds permission when parent has access but nested team does not" do
          @closed_team.add_repository(@repo, :push)

          assert_equal "push", @closed_team.permission_for(@repo)
          assert_nil @closed_child_team.permission_for(@repo)

          resp, queries = log_queries { @closed_child_team.add_or_update_repository @repo, :push }

          assert_equal Team::ModifyRepositoryStatus::SUCCESS, resp
          assert queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
          assert_equal "push", @closed_child_team.permission_for(@repo)
        end

        test "adds permission when nested team has access but parent does not" do
          @closed_child_team.add_repository(@repo, :pull)

          assert_nil @closed_team.permission_for(@repo)
          assert_equal "pull", @closed_child_team.permission_for(@repo)

          resp, queries = log_queries { @closed_team.add_or_update_repository @repo, :pull }

          assert_equal Team::ModifyRepositoryStatus::SUCCESS, resp
          assert queries.any? { |q| /INSERT INTO `abilities`/ =~ q.sql }
          assert_equal "pull", @closed_team.permission_for(@repo)
        end
      end

      test "#update_repository_permission subscribes members to the repo when permission is changed from pull to push" do
        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.auto_subscribe = true
        end

        @org.add_member(@user)
        @team.add_member(@user)
        @team.add_repository(@repo, :pull)

        Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: "Repository", id: @repo.id))

        assert_difference "GitHub.newsies.count_subscribers(@repo).count", 1 do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) { @team.update_repository_permission(@repo, :push) }
        end
      end

      test "#update_repository_permission subscribes members to the repo when permission is changed from pull to push as an ET team" do
        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.auto_subscribe = true
        end

        @org.add_member(@user)
        @team.stubs(:enterprise_team_managed?).returns(true)
        @team.bulk_add_members([@user], caller_type: :enterprise_team)
        @team.add_repository(@repo, :pull)

        Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: "Repository", id: @repo.id))

        assert_difference "GitHub.newsies.count_subscribers(@repo).count", 1 do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) { @team.update_repository_permission(@repo, :push) }
        end
      end

      if GitHub.enterprise?
        test "#update_repository_permission subscribes members to forks of repos" do
          org = create(:organization, plan: "bronze")
          org.allow_private_repository_forking(actor: org.admins.first)
          repo = create(:private_repository, owner: org, from_example: :simple)
          team = create :team, organization: org
          team.add_repository(repo, :pull)

          users = Array.new(2).map do
            user = create :user
            GitHub.newsies.get_and_update_settings(user) do |settings|
              settings.auto_subscribe = true
            end
            team.add_member(user)
            user
          end

          perform_enqueued_jobs(only: [Newsies::DeleteAllForListJob]) do
            Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: "Repository", id: @repo.id))
          end

          forker = users.first
          only = [RepositoryAddTeamsJob]
          fork, _ = perform_enqueued_jobs(only: only) { repo.fork(forker: forker) }

          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUsersToRepositoryJob]) do
            team.update_repository_permission(fork, :push)
            assert_same_elements users, GitHub.newsies.subscribers(fork)
          end
        end
      else
        test "#update_repository_permission does not subscribe members to forks of repos" do
          skip "this test does not work correctly"
          org = create(:organization, plan: "bronze")
          org.allow_private_repository_forking(actor: org.admins.first)
          repo = create(:private_repository, owner: org, from_example: :simple)
          team = create :team, organization: org
          team.add_repository(repo, :pull)

          users = Array.new(2).map do
            user = create :user
            GitHub.newsies.get_and_update_settings(user) do |settings|
              settings.auto_subscribe = true
            end
            team.add_member(user)
            user
          end

          only = [Newsies::DeleteAllForListJob]
          perform_enqueued_jobs(only: only) do
            Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: "Repository", id: @repo.id))
          end

          forker = users.first
          only = [AddToSearchIndexJob, CheckForSpamJob, DeliverHookEventJob, Newsies::AutoSubscribeUsersToRepositoryJob, Newsies::DeleteAllForListJob, ProcessEventJob, RemoveFromSearchIndexJob, RepositoryAddTeamsJob, RepositoryOrchestrationJob, TeamAddForksJob, TradeControls::ComplianceCheckJob, UpdateEventFeedsJob, ProcessEmailDomainForReputationDataJob]
          fork, _ = perform_enqueued_jobs(only: only) { repo.fork(forker: forker) }

          only = [AddToSearchIndexJob, CheckForSpamJob, DeliverHookEventJob, Newsies::AutoSubscribeUsersToRepositoryJob, Newsies::DeleteAllForListJob, ProcessEventJob, RemoveFromSearchIndexJob, RepositoryAddTeamsJob, RepositoryOrchestrationJob, TeamAddForksJob, TradeControls::ComplianceCheckJob, UpdateEventFeedsJob, ProcessEmailDomainForReputationDataJob]
          perform_enqueued_jobs(only: only) do
            team.update_repository_permission(fork, :push)
            assert_empty GitHub.newsies.subscribers(fork)
          end
        end

        test "#update_repository_permission never subscribes members to descendent forks" do
          @org.allow_private_repository_forking(actor: @org.admins.first)
          repo = create(:private_repository, owner: @org, from_example: :simple)
          @team.add_repository(repo, :pull)

          users = Array.new(3).map do
            user = create :user
            GitHub.newsies.get_and_update_settings(user) do |settings|
              settings.auto_subscribe = true
            end
            @team.add_member(user)
            user
          end

          Notifications::Subscriptions.async_delete_list_subscriptions(Notifications::Subject.new(type: "Repository", id: @repo.id))

          first_forker = users[0]
          second_forker = users[1]

          only = [RepositoryAddTeamsJob, RepositoryOrchestrationJob, TeamAddForksJob]
          first_fork, _ = perform_enqueued_jobs(only: only) do
            repo.fork(forker: first_forker)
          end
          first_fork.allow_private_repository_forking(actor: first_forker)

          only = [Newsies::AutoSubscribeUsersToRepositoryJob, RepositoryAddTeamsJob, RepositoryOrchestrationJob, TeamAddForksJob]
          second_fork, _ = perform_enqueued_jobs(only: only) do
            first_fork.fork(forker: second_forker)
          end

          @team.update_repository_permission(second_fork, :push)
          assert_empty GitHub.newsies.subscribers(second_fork)
        end
      end

      test "#update_repository_permission enqueues a background job for parent repos" do
        @team.add_repository @repo, :push
        @team.add_member(@user, adder: @owner)

        only = [RepositoryAddTeamsJob]
        forked_repo, _ = perform_enqueued_jobs(only: only) { @repo.fork(forker: @owner) }
        forked_repo.allow_private_repository_forking(actor: @owner)
        only = [RepositoryAddTeamsJob]
        fork_of_fork, _ = perform_enqueued_jobs(only: only) { forked_repo.fork(forker: @user) }

        perform_enqueued_jobs(only: [TeamUpdateForkedRepositoryPermissionsJob]) do
          @team.update_repository_permission(@repo, "pull")
        end

        assert_equal "pull", @team.permission_for(forked_repo)
        assert_equal "pull", @team.permission_for(fork_of_fork)
      end

      test "#update_repository_permission does not enqueue a background job for forks" do
        @team.add_repository @repo, :push
        @team.add_member(@user, adder: @owner)

        forked_repo = create(:fork_repository, forker: @owner, fork_repo: @repo)
        fork_of_fork = create(:fork_repository, forker: @user, fork_repo: forked_repo)

        perform_enqueued_jobs(only: [DeliverHookEventJob]) do
          @team.update_repository_permission(forked_repo, "pull")
        end

        refute_equal @team.permission_for(forked_repo), @team.permission_for(fork_of_fork)
      end

      test "#add_or_update_repository adds repo to team if it isn't already added" do
        @team = create :team, organization: @org

        refute @team.batched_repositories.include?(@repo)

        @team.add_or_update_repository(@repo, "pull")

        assert @team.batched_repositories.include?(@repo)
      end

      test "#add_or_update_repository updates repo permissions if the team is already added" do
        @team.add_repository @repo, :push

        assert @team.batched_repositories.include?(@repo)
        assert_equal "push", @team.permission_for(@repo)

        @team.add_or_update_repository(@repo, "admin")

        assert @team.batched_repositories.include?(@repo)
        assert_equal "admin", @team.permission_for(@repo)
      end

      test "#add_or_update_repository properly downgrades repo permissions" do
        @team.add_repository @repo, :push

        assert @team.batched_repositories.include?(@repo)
        assert_equal "push", @team.permission_for(@repo)

        @team.add_or_update_repository(@repo, "pull")

        assert @team.batched_repositories.include?(@repo)
        assert_equal "pull", @team.permission_for(@repo)
        refute_able @team, :write, @repo
        refute_able @team, :admin, @repo
      end
    end
  end

  test "#add_repository_directly grants admin to the team on a repo" do
    @team.add_repository_directly @repo
    assert_able @team, :admin, @repo
  end

  test "#add_repository_directly won't fail if a repo is added twice" do
    @team.add_repository_directly @repo
    @team.add_repository_directly @repo
    assert_able @team, :admin, @repo
  end

  test "#remove_repository_directly removes abilities on a team from a repo" do
    @team.add_repository_directly @repo
    assert_able @team, :admin, @repo

    @team.remove_repository_directly @repo
    refute_able @team, :admin, @repo
  end

  test "#remove_repository enqueues a job to purge incidental relations" do
    @team.add_repository_directly @repo
    @team.add_member @user

    assert_enqueued_jobs 1, only: ClearTeamMembershipsJob, queue: "team_remove_members" do
      GitHub.context.push(actor_id: @owner.id) do
        @team.remove_repository @repo
      end
    end

    assert_enqueued_with(job: ClearTeamMembershipsJob, args: [@org.id, [@user.id], repo: @repo.id], queue: "team_remove_members")
  end

  context "add_project" do
    test "adds the project to the team's projects list" do
      refute_includes @team.projects, @project

      @team.add_project(@project, :read)

      assert_includes @team.projects, @project
    end

    test "grants team members the specified permission on the project" do
      refute @project.readable_by?(@team)

      @team.add_project(@project, :read)

      assert @project.readable_by?(@team)
    end
  end

  context "update_project_permission" do
    test "leaves the project in the team's projects list" do
      @team.add_project(@project, :read)

      assert_includes @team.projects, @project

      @team.update_project_permission(@project, :write)

      assert_includes @team.projects, @project
    end

    test "changes team members permission on the project to the specified permission" do
      @team.add_project(@project, :read)

      refute @project.writable_by?(@team)

      @team.update_project_permission(@project, :write)

      assert @project.writable_by?(@team)
    end
  end

  context "remove_project" do
    test "removes the project from the team's projects list" do
      @team.add_project(@project, :read)

      assert_includes @team.projects, @project

      @team.remove_project(@project)

      refute_includes @team.projects, @project
    end

    test "revokes team members permission on the project" do
      @team.add_project(@project, :read)

      assert @project.readable_by?(@team)

      @team.remove_project(@project)

      refute @project.readable_by?(@team)
    end
  end

  context "#ranked_members_for" do
    test "returns team members with the ones the given user follows first" do
      @team.add_member(@user)

      followed_user1 = create(:user, login: "followed-user1") # not in team
      @user.follow(followed_user1)

      unfollowed_user1 = create(:user, login: "unfollowed-user1")
      @team.add_member(unfollowed_user1)

      unfollowed_user2 = create(:user, login: "unfollowed-user2") # not in team

      followed_user2 = create(:user, login: "followed-user2")
      @user.follow(followed_user2)
      @team.add_member(followed_user2)

      scope = User.where(id: @team.member_ids)
      actual = @team.ranked_members_for(@user, scope: scope)

      assert_equal [followed_user2, @user, unfollowed_user1], actual
    end
  end

  context "members" do
    test "#members returns users who are part of the team" do
      @team.add_member @user
      assert_equal [@user], @team.members
    end

    test "#add_member keeps the team's associations fresh" do
      assert_equal [], @team.members
      assert_equal [], @team.member_ids
      @team.add_member @user
      assert_equal [@user], @team.members
      assert_equal [@user.id], @team.member_ids
    end

    context "add_member" do
      test "allows changes to an enterprise managed team by the enterprise team", skip_enterprise: true do
        setup_enterprise_team
        @emu_team.add_member(@emu_admin, caller_type: :enterprise_team)
        assert_equal [@emu_admin.id], @emu_team.member_ids
      end

      test "does not allow changes to an enterprise managed team by anything else", skip_enterprise: true do
        setup_enterprise_team
        @emu_team.add_member(@emu_admin)
        assert_empty @emu_team.member_ids
      end

      test "subscribes the user to all org-owned repositories that the team grants direct push access to" do
        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.auto_subscribe = true
        end
        @team.add_repository(@repo, :push)
        @org.add_member(@user)

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", 1) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
            @team.add_member(@user)
          end
        end
      end

      test "subscribes the user to all org-owned repositories that the team inherits push access to" do
        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.auto_subscribe = true
        end
        @parent_team.add_repository(@repo, :push)
        @org.add_member(@user)

        assert_difference("GitHub.newsies.count_subscribers(@repo).count", 1) do
          perform_enqueued_jobs(only: [Newsies::AutoSubscribeUserToRepositoriesJob]) do
            @child_team.add_member(@user)
          end
        end
      end

      test "subscribes new members to the team if auto-watching is enabled" do

        GitHub.newsies.get_and_update_settings(@user) do |settings|
          settings.auto_subscribe_teams = true
        end

        assert GitHub.newsies.settings(@user).auto_subscribe_teams?

        assert_difference("GitHub.newsies.count_subscribers(@team).count", 1) do
          @team.add_member(@user)
          assert_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
        end
      end

      test "subscribes new members to all parent teams" do
        root_team = create(:team, privacy: :closed)
        org = root_team.organization
        parent_team = create(:team, organization: org, parent_team_id: root_team.id, privacy: :closed)
        team = create(:team, organization: org, parent_team_id: parent_team.id, privacy: :closed)
        user = create :user

        refute GitHub.newsies.subscription_status(user, root_team).valid?,
          "Expected user to be unsubscribed from root team."
        refute GitHub.newsies.subscription_status(user, parent_team).valid?,
          "Expected user to be unsubscribed from root team."

        team.add_member(user)

        assert GitHub.newsies.subscription_status(user, root_team).valid?,
          "Expected user to be subscribed to root team."
        assert GitHub.newsies.subscription_status(user, parent_team).valid?,
          "Expected user to be subscribed to parent team."
      end

      test "with invitations bypassed, adds unaffiliated user to the team" do
        GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

        user = create :user
        @team.add_member(user)

        assert @team.member?(user), "user should become a member of the team"
        assert @org.member?(user), "user should become a member of the org"
      end

      test "does not allow a non-user to be added as a member" do
        other_org = create :organization
        assert_equal Team::AddMemberStatus::NOT_USER, @team.add_member(other_org)
      end

      test "does not allow a bot to be added as a member" do
        bot = create(:integration).bot
        assert_equal Team::AddMemberStatus::NOT_USER, @team.add_member(bot)
      end

      test "does not allow a mannequin to be added as a member" do
        mannequin = create(:mannequin)
        assert_equal Team::AddMemberStatus::NOT_USER, @team.add_member(mannequin)
      end

      test "with invitations bypassed, does not add member if user does not meet 2fa requirement" do
        GitHub.flipper[:members_without_2fa_allowed].disable
        GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

        user = create :user
        twofaorg = create :organization
        twofaorg.enable_two_factor_requirement(actor: twofaorg.admin)
        team = create :team, organization: twofaorg
        assert_equal Team::AddMemberStatus::NO_2FA, team.add_member(user)
        refute twofaorg.member?(user), "user should not become a member of the org"
        refute team.member?(user), "user should not become a member of the team"
        refute_includes user.teams, team, "user should not have the team in their list of teams"
      end

      test "without invitations bypassed, does not add member if user does not meet 2fa requirement" do
        GitHub.flipper[:members_without_2fa_allowed].disable
        user = create :user
        org = create :organization
        org.enable_two_factor_requirement(actor: org.admin)
        team = create :team, organization: org

        refute org.two_factor_requirement_met_by?(user), "#{user} should not meet 2fa requirement"

        assert_equal Team::AddMemberStatus::NO_2FA, team.add_member(user)

        refute org.member?(user), "user should not become a member of the org"
        refute team.member?(user), "user should not become a member of the team"
        refute_includes user.teams, team, "user should not have the team in their list of teams"
      end

      test "with invitations bypassed, does not add member to github/employees if user has SMS 2FA", skip_enterprise: true, skip_in_multitenant_mode: true, skip_with_all_emus: true do
        GitHub.flipper[:github_employees_no_sms_2fa].enable
        GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

        user = create :user
        create(:user_two_factor_primary_sms_registration, user: user).save!

        assert_equal Team::AddMemberStatus::GITHUB_EMPLOYEE_NO_SMS_2FA, @github_employees_team.add_member(user.reload)

        refute github_org.member?(user), "user should not become a member of the org"
        refute @github_employees_team.member?(user), "user should not become a member of the team"
        refute_includes user.teams, @github_employees_team, "user should not have the team in their list of teams"
      end

      test "without invitations bypassed, does not add member to github/employees if user has SMS 2FA", skip_enterprise: true, skip_in_multitenant_mode: true, skip_with_all_emus: true do
        GitHub.flipper[:github_employees_no_sms_2fa].enable
        GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

        user = create :user
        create(:user_two_factor_primary_sms_registration, user: user).save!

        assert_equal Team::AddMemberStatus::GITHUB_EMPLOYEE_NO_SMS_2FA, @github_employees_team.add_member(user.reload)

        refute github_org.member?(user), "user should not become a member of the org"
        refute @github_employees_team.member?(user), "user should not become a member of the team"
        refute_includes user.teams, @github_employees_team, "user should not have the team in their list of teams"
      end

      test "does not add member if user does not meet the Organization SAML SSO requirement" do
        user = create :user
        saml_org = create :business_plus_org
        saml_identity = create(:external_identity, org: saml_org)
        saml_org.saml_provider.enforce!
        team = create :team, organization: saml_org

        refute saml_org.saml_sso_requirement_met_by?(user), "#{user} should not meet SAML SSO requirement"

        assert_equal Team::AddMemberStatus::NO_SAML_SSO, team.add_member(user)

        refute saml_org.member?(user), "user should not become a member of the org"
        refute team.member?(user), "user should not become a member of the team"
        refute_includes user.teams, team, "user should not have the team in their list of teams"
      end

      if GitHub.external_identity_session_enforcement_enabled?
        test "does not add member if user does not meet the Organization's Business SAML SSO requirement" do
          user = create :user
          business = create(:business_saml_provider).business
          org = create(:business_plus_organization, business: business)

          team = create :team, organization: org

          refute business.saml_sso_requirement_met_by?(user), "#{user} should not meet SAML SSO requirement"

          assert_equal Team::AddMemberStatus::NO_SAML_SSO, team.add_member(user)

          refute org.member?(user), "user should not become a member of the org"
          refute team.member?(user), "user should not become a member of the team"
          refute_includes user.teams, team, "user should not have the team in their list of teams"
        end

        test "does not add member if user does not meet the Organization's Business External SSO requirement" do
          user = create :user
          business = create(:business_saml_provider).business
          org = create(:business_plus_organization, business: business)

          team = create :team, organization: org

          refute business.external_sso_requirement_met_by?(user), "#{user} should not meet SAML SSO requirement"

          assert_equal Team::AddMemberStatus::NO_SAML_SSO, team.add_member(user)

          refute org.member?(user), "user should not become a member of the org"
          refute team.member?(user), "user should not become a member of the team"
          refute_includes user.teams, team, "user should not have the team in their list of teams"
        end

        test "adds member if user meets the Organization's EMU Business OIDC requirement" do
          user = create :emu, provider_type: :oidc
          business = user.enterprise_managed_business
          org = create(:enterprise_linked_organization, business: business, admin: user)
          team = create :team, organization: org

          assert business.external_sso_requirement_met_by?(user)
        end
      end

      test "with pending team membership request, cancels membership request" do
        user = create :user
        @team.request_membership(user)

        assert @team.pending_team_membership_requests.any?
        @team.add_member(user)
        refute(
          @team.pending_team_membership_requests.any?,
          "pending membership request should be cancelled")
      end
    end

    context "remove_member" do
      test "preserves the user's org membership if they're removed from their last team" do
        member = create :user
        @team.add_member(member)

        assert @org.direct_member?(member)

        @team.remove_member(member)

        assert @org.direct_member?(member)
      end

      test "does not call enterprise_team_managed? on an emu team", skip_enterprise: true do
        setup_enterprise_team
        @emu_team.bulk_add_members([@emu_admin], caller_type: :enterprise_team)

        Team.any_instance.expects(:enterprise_team_managed?).never
        @emu_team.remove_member(@emu_admin, caller_type: :enterprise_team)
        assert_empty @emu_team.member_ids
      end

      test "does not call enterprise_team_managed? on a non-emu team" do
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
        member = create :user
        @team.add_member(member)

        assert @org.direct_member?(member)
        Team.any_instance.expects(:enterprise_team_managed?).never

        @team.remove_member(member, caller_type: :enterprise_team)
      end

      test "notifies the member" do
        user = create :user
        @org.add_member user
        @team.add_member user
        @team.add_repository @repo, :pull

        assert_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            @team.remove_member user
          end
        end
      end

      test "does not notify the member if the user is suspended" do
        user = create :suspended_user
        @org.add_member user
        @team.add_member user
        @team.add_repository @repo, :pull

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            @team.remove_member user
          end
        end
      end

      test "enqueues a job to purge incidental relations" do
        user = create :user
        @org.add_member user
        @team.add_member user
        @team.add_repository @repo, :pull

        assert_enqueued_jobs 1, only: ClearTeamMembershipsJob, queue: "team_remove_members" do
          GitHub.context.push(actor_id: @owner.id) do
            @team.remove_member(user)
          end
        end

        assert_enqueued_with(job: ClearTeamMembershipsJob, args: [@org.id, [@repo.id], user: user.id], queue: "team_remove_members")
      end

      test "removes inaccessible forks for user" do
        @org.update_default_repository_permission(:none, actor: @owner)

        @team.add_member(@user)

        private_repo = create(:private_repository, owner: @org)
        refute private_repo.pullable_by?(@user)
        @team.add_repository private_repo, :pull
        assert private_repo.pullable_by?(@user)

        user_fork = create(:fork_repository, forker: @user, fork_repo: private_repo)

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @team.remove_member(@user) }
        assert_nil Repositories::Public.find_active(user_fork.id)
      end

      test "removes inaccessible forks when permission to source repo was inherited through the team" do
        @org.update_default_repository_permission(:none, actor: @owner)

        @child_team.add_member(@user)

        parent_repository = create(:private_repository, owner: @org, name: "parent-repository")
        refute parent_repository.pullable_by?(@user)
        @parent_team.add_repository parent_repository, :pull
        assert parent_repository.pullable_by?(@user)

        user_fork = create(:fork_repository, forker: @user, fork_repo: parent_repository)

        only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @child_team.remove_member(@user) }

        assert_nil Repositories::Public.find_active(user_fork.id)
      end

      test "does not notify the member if they were removed from org" do
        @org.add_member @user
        @team.add_member @user
        @team.add_repository @repo, :pull

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @team.remove_member(@user, send_notification: false)
        end
      end

      test "does not notify the member if team has no repos" do
        @org.add_member @user
        @team.add_member @user

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @team.remove_member @user
        end
      end

      test "clears the user's association cache" do
        @team.add_member(@user)

        assert_includes @user.teams, @team

        @team.remove_member(@user)

        # Note: No explicit reload here, since we want Team#remove_member to do
        # it for us.
        refute_includes @user.teams, @team
      end

      test "unsubscribes the user from the team" do
        @team.add_member(@user)

        assert_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?

        assert_difference("GitHub.newsies.count_subscribers(@team).count", -1) do
          perform_enqueued_jobs(only: [Newsies::DeleteAllForUserAndListsJob]) do
            @team.remove_member(@user)
            refute_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
          end
        end
      end

      test "unsubscribes the user from the parent teams" do
        root_team = create(:team, privacy: :closed)
        org = root_team.organization
        parent_team = create(:team, organization: org, parent_team_id: root_team.id, privacy: :closed)
        team = create(:team, organization: org, parent_team_id: parent_team.id, privacy: :closed)

        team.add_member(@user)

        assert_predicate GitHub.newsies.subscription_status(@user, root_team), :subscribed?,
          "Expected user to be subscribed to root team."
        assert_predicate GitHub.newsies.subscription_status(@user, parent_team), :subscribed?,
          "Expected user to be subscribed to parent team."

        only = [DeleteDependentAbilitiesJob, Newsies::DeleteAllForUserAndListsJob]
        perform_enqueued_jobs(only: only) do
          team.remove_member(@user)
        end

        refute_predicate GitHub.newsies.subscription_status(@user, root_team), :subscribed?,
          "Expected user to be unsubscribed from root team."
        refute_predicate GitHub.newsies.subscription_status(@user, parent_team), :subscribed?,
          "Expected user to be unsubscribed from parent team."
      end

      test "does not unsubscribe the user from parent teams they are a member of" do
        root_team = create(:team, privacy: :closed)
        org = root_team.organization
        grand_parent_team = create(:team, organization: org, parent_team_id: root_team.id, privacy: :closed)
        parent_team = create(:team, organization: org, parent_team_id: grand_parent_team.id, privacy: :closed)
        team = create(:team, organization: org, parent_team_id: parent_team.id, privacy: :closed)

        team.add_member(@user)
        grand_parent_team.add_member(@user)

        assert_predicate GitHub.newsies.subscription_status(@user, root_team), :subscribed?,
          "Expected user to be subscribed to root team."
        assert_predicate GitHub.newsies.subscription_status(@user, parent_team), :subscribed?,
          "Expected user to be subscribed to parent team."
        assert_predicate GitHub.newsies.subscription_status(@user, grand_parent_team), :subscribed?,
          "Expected user to be subscribed to grand parent team."

        only = [DeleteDependentAbilitiesJob, Newsies::DeleteAllForUserAndListsJob]
        perform_enqueued_jobs(only: only) do
          team.remove_member(@user)
        end

        assert_predicate GitHub.newsies.subscription_status(@user, root_team), :subscribed?,
          "Expected user to be subscribed to root team."
        refute_predicate GitHub.newsies.subscription_status(@user, parent_team), :subscribed?,
          "Expected user to be unsubscribed from parent team."
        assert_predicate GitHub.newsies.subscription_status(@user, grand_parent_team), :subscribed?,
          "Expected user to be subscribed to grand parent team."
      end
    end

    context "bulk_remove_members" do
      # TODO: Add GHEC and SCIM based tests when we support ESM on those runtimes
      test "preserves the users' org membership if they're removed from their last team" do
        GitHub.stubs(:esm_enabled?).returns(true)

        member = create :user
        member2 = create :user
        @team.add_member(member)
        @team.add_member(member2)

        assert @org.direct_member?(member)
        assert @org.direct_member?(member2)

        @team.bulk_remove_members(users: [member, member2])

        assert @org.direct_member?(member)
        assert @org.direct_member?(member2)
      end

      test "does not call enterprise_team_managed? on a non-emu team" do
        GitHub.stubs(:esm_enabled?).returns(true)
        EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

        member = create :user
        @team.add_member(member)

        assert @org.direct_member?(member)
        Team.any_instance.expects(:enterprise_team_managed?).never

        @team.bulk_remove_members(users: [member], caller_type: :enterprise_team)
      end

      test "notifies the members" do
        GitHub.stubs(:esm_enabled?).returns(true)

        user = create :user
        @org.add_member user
        @team.add_member user

        user2 = create :user
        @org.add_member user2
        @team.add_member user2

        @team.add_repository @repo, :pull

        assert_difference "ActionMailer::Base.deliveries.size", 2 do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            @team.bulk_remove_members(users: [user, user2])
          end
        end
      end

      test "does not notify members if they are suspended" do
        user = create :suspended_user
        @org.add_member user
        @team.add_member user

        user2 = create :suspended_user
        @org.add_member user2
        @team.add_member user2

        @team.add_repository @repo, :pull

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          perform_enqueued_jobs(only: [ApplicationDeliveryJob]) do
            @team.bulk_remove_members(users: [user, user2])
          end
        end
      end

      test "enqueues a job to purge incidental relations" do
        GitHub.stubs(:esm_enabled?).returns(true)

        user = create :user
        @org.add_member user
        @team.add_member user

        user2 = create :user
        @org.add_member user2
        @team.add_member user2

        @team.add_repository @repo, :pull

        assert_enqueued_jobs 2, only: ClearTeamMembershipsJob, queue: "team_remove_members" do
          GitHub.context.push(actor_id: @owner.id) do
            @team.bulk_remove_members(users: [user, user2])
          end
        end

        assert_enqueued_with(job: ClearTeamMembershipsJob, args: [@org.id, [@repo.id], user: user.id], queue: "team_remove_members")
        assert_enqueued_with(job: ClearTeamMembershipsJob, args: [@org.id, [@repo.id], user: user2.id], queue: "team_remove_members")
      end

      test "removes inaccessible forks for users" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @org.update_default_repository_permission(:none, actor: @owner)

        @team.add_member(@user)
        @team.add_member(@another_user)

        private_repo = create(:private_repository, owner: @org)
        refute private_repo.pullable_by?(@user)
        refute private_repo.pullable_by?(@another_user)
        @team.add_repository private_repo, :pull
        assert private_repo.pullable_by?(@user)
        assert private_repo.pullable_by?(@another_user)

        user_fork = create(:fork_repository, forker: @user, fork_repo: private_repo)
        user2_fork = create(:fork_repository, forker: @another_user, fork_repo: private_repo)

        only = [RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @team.bulk_remove_members(users: [@user, @another_user]) }
        assert_nil Repositories::Public.find_active(user_fork.id)
        assert_nil Repositories::Public.find_active(user2_fork.id)
      end

      test "removes inaccessible forks when permission to source repo was inherited through the team" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @org.update_default_repository_permission(:none, actor: @owner)

        @child_team.add_member(@user)
        @child_team.add_member(@another_user)

        parent_repo = create(:private_repository, owner: @org, name: "parent-repository")
        refute parent_repo.pullable_by?(@user)
        refute parent_repo.pullable_by?(@another_user)
        @parent_team.add_repository parent_repo, :pull
        assert parent_repo.pullable_by?(@user)
        assert parent_repo.pullable_by?(@another_user)

        user_fork = create(:fork_repository, forker: @user, fork_repo: parent_repo)
        user2_fork = create(:fork_repository, forker: @another_user, fork_repo: parent_repo)

        only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, RepositoryOrchestrationJob]
        perform_enqueued_jobs(only: only) { @child_team.bulk_remove_members(users: [@user, @another_user]) }
        assert_nil Repositories::Public.find_active(user_fork.id)
        assert_nil Repositories::Public.find_active(user2_fork.id)
      end

      test "does not notify members if they were removed from org" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @org.add_member @user
        @team.add_member @user
        @team.add_repository @repo, :pull

        @org.add_member @another_user
        @team.add_member @another_user

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @team.bulk_remove_members(users: [@user, @another_user], send_notification: false)
        end
      end

      test "does not notify members if team has no repos" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @org.add_member @user
        @team.add_member @user

        @org.add_member @another_user
        @team.add_member @another_user

        assert_no_difference "ActionMailer::Base.deliveries.size" do
          @team.bulk_remove_members(users: [@user, @another_user], send_notification: false)
        end
      end

      test "clears the users' association cache" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @team.add_member(@user)
        @team.add_member(@another_user)

        assert_includes @user.teams, @team
        assert_includes @another_user.teams, @team

        @team.bulk_remove_members(users: [@user, @another_user])

        # Note: No explicit reload here, since we want Team#bulk_remove_members to do
        # it for us.
        refute_includes @user.teams, @team
        refute_includes @another_user.teams, @team
      end

      test "unsubscribes users from the team" do
        GitHub.stubs(:esm_enabled?).returns(true)

        @team.add_member(@user)
        @team.add_member(@another_user)

        assert_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
        assert_predicate GitHub.newsies.subscription_status(@another_user, @team), :subscribed?

        assert_difference("GitHub.newsies.count_subscribers(@team).count", -2) do
          perform_enqueued_jobs(only: [Newsies::DeleteAllForUserAndListsJob]) do
            @team.bulk_remove_members(users: [@user, @another_user])
            refute_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
            refute_predicate GitHub.newsies.subscription_status(@another_user, @team), :subscribed?
          end
        end
      end

      test "unsubscribes users from the parent teams" do
        GitHub.stubs(:esm_enabled?).returns(true)

        root_team = create(:team, privacy: :closed)
        org = root_team.organization
        parent_team = create(:team, organization: org, parent_team_id: root_team.id, privacy: :closed)
        team = create(:team, organization: org, parent_team_id: parent_team.id, privacy: :closed)

        team.add_member(@user)
        team.add_member(@another_user)

        [@user, @another_user].each do |user|
          assert_predicate GitHub.newsies.subscription_status(user, root_team), :subscribed?,
            "Expected user to be subscribed to root team."
          assert_predicate GitHub.newsies.subscription_status(user, parent_team), :subscribed?,
            "Expected user to be subscribed to parent team."
        end

        only = [DeleteDependentAbilitiesJob, Newsies::DeleteAllForUserAndListsJob]
        perform_enqueued_jobs(only: only) do
          team.bulk_remove_members(users: [@user, @another_user])
        end

        [@user, @another_user].each do |user|
          refute_predicate GitHub.newsies.subscription_status(user, root_team), :subscribed?,
            "Expected user to be unsubscribed from root team."
          refute_predicate GitHub.newsies.subscription_status(user, parent_team), :subscribed?,
            "Expected user to be unsubscribed from parent team."
        end
      end

      test "does not unsubscribe users from parent teams they are a member of" do
        GitHub.stubs(:esm_enabled?).returns(true)

        root_team = create(:team, privacy: :closed)
        org = root_team.organization
        grand_parent_team = create(:team, organization: org, parent_team_id: root_team.id, privacy: :closed)
        parent_team = create(:team, organization: org, parent_team_id: grand_parent_team.id, privacy: :closed)
        team = create(:team, organization: org, parent_team_id: parent_team.id, privacy: :closed)

        team.add_member(@user)
        grand_parent_team.add_member(@user)

        team.add_member(@another_user)
        grand_parent_team.add_member(@another_user)

        [@user, @another_user].each do |user|
          assert_predicate GitHub.newsies.subscription_status(user, root_team), :subscribed?,
            "Expected user to be subscribed to root team."
          assert_predicate GitHub.newsies.subscription_status(user, parent_team), :subscribed?,
            "Expected user to be subscribed to parent team."
          assert_predicate GitHub.newsies.subscription_status(user, grand_parent_team), :subscribed?,
            "Expected user to be subscribed to grand parent team."
        end

        only = [DeleteDependentAbilitiesJob, Newsies::DeleteAllForUserAndListsJob]
        perform_enqueued_jobs(only: only) do
          team.bulk_remove_members(users: [@user, @another_user])
        end

        [@user, @another_user].each do |user|
          assert_predicate GitHub.newsies.subscription_status(user, root_team), :subscribed?,
            "Expected user to be subscribed to root team."
          refute_predicate GitHub.newsies.subscription_status(user, parent_team), :subscribed?,
            "Expected user to be unsubscribed from parent team."
          assert_predicate GitHub.newsies.subscription_status(user, grand_parent_team), :subscribed?,
            "Expected user to be subscribed to grand parent team."
        end
      end

      test "does not instrument when enterprise team caller and esm enabled" do
        GitHub.stubs(:esm_enabled?).returns(true)
        Instrumentation::Model.expects(:instrument).never

        @team.add_member(@user)
        @team.add_member(@another_user)

        @team.bulk_remove_members(users: [@user, @another_user])
      end
    end
  end

  test "#members_sorted_by_login returns members, sorted by login" do
    user_a = create(:user, login: "Zebedee")
    user_b = create(:user, login: "Alfred")
    @team.add_member user_a
    @team.add_member user_b

    expected = [user_b, user_a]
    assert_equal expected, @team.members_sorted_by_login
  end

  test "#maintainers_sorted_by_login returns team maintainers, sorted by login" do
    user_a = create(:user, login: "Zebedee")
    user_b = create(:user, login: "Alfred")
    @org.add_member user_a
    @org.add_member user_b
    @team.add_member user_a
    @team.add_member user_b
    @team.promote_maintainer user_a
    @team.promote_maintainer user_b

    expected = [user_b, user_a]
    assert_equal expected, @team.maintainers_sorted_by_login
  end

  test "doesn't change existing repo permissions when changing a team from pull to push permission" do
    team = create :team, organization: @org, permission: "push"
    team.add_repository(@repo, :push)

    assert_able team, :write, @repo

    team.update! permission: "pull"

    assert_able team, :write, @repo
  end

  test "doesn't change existing repo permissions when changing a team from push to pull permission" do
    team = create :team, organization: @org, permission: "pull"
    team.add_repository(@repo, :pull)

    assert_able team, :read, @repo
    refute_able team, :write, @repo

    team.update! permission: "push"

    assert_able team, :read, @repo
    refute_able team, :write, @repo
  end

  context "valid_privacy?" do
    test "true for a valid privacy in symbol form" do
      assert Team.valid_privacy?(:closed)
    end

    test "true for a valid privacy in string form" do
      assert Team.valid_privacy?("closed")
    end

    test "false for an invalid privacy" do
      refute Team.valid_privacy?(:invalid)
    end

    test "false for nil" do
      refute Team.valid_privacy?(nil)
    end
  end

  context "secret?" do
    test "returns true when team is secret" do
      team = create :team, privacy: :secret
      assert_predicate team, :secret?
    end

    test "returns false when team is closed" do
      team = create :team, privacy: :closed
      refute_predicate team, :secret?
    end
  end

  context "joinable_by?" do
    test "returns true when the user is on the owners team" do
      assert @team.joinable_by?(@org.admins.first)
    end

    test "returns false when the user is not on the owners team"  do
      @team.add_member @user
      refute @team.joinable_by?(@user)
    end

    test "returns false when the user is already on the team" do
      @team.add_member @org.admins.first
      refute @team.joinable_by?(@org.admins.first)
    end

    test "returns false when the user is not in the org" do
      refute @team.joinable_by?(@user)
    end
  end

  context "team membership requests" do
    test "membership can be requested for a user" do
      assert_difference "TeamMembershipRequest.count", 1 do
        @team.request_membership(@user)
      end
      request = TeamMembershipRequest.last
      assert_equal T.must(request).team, @team
      assert_equal T.must(request).requester, @user
    end
  end

  context "instrumentation" do
    test "event_context returns serialized team" do
      context = @team.event_context
      expected_context = {
        team: @team.to_s,
        team_id: @team.id,
      }

      assert_equal expected_context, context
    end

    test "instruments team create" do
      events = subscribe "team.create"
      @team = create :team, organization: @org
      expected_payload = {
        ldap_mapped: @team.ldap_mapped?,
        team: @team.to_s,
        team_id: @team.id,
        note: "Team #{@team}",
        org: @org.login,
        org_id: @org.id,
        actor: User.ghost.login,
        actor_id: User.ghost.id,
        spammy: false,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments team rename" do
      events = subscribe "team.rename"
      team = create :team, organization: @org, name: "new-team", privacy: :closed
      team.update! name: "new-team-renamed"

      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        note:        "Team #{team}",
        name:        "new-team-renamed",
        name_was:    "new-team",
        team:        team.to_s,
        team_id:     team.id,
        org:         @org.login,
        org_id:      @org.id,
      }

      assert event = events.pop, "An event was expected"
      assert_equal expected_payload, event.payload
    end

    test "doesn't instrument team rename on update unless actually renamed" do
      events = subscribe "team.rename"
      team = create :team, organization: @org, name: "new-team", privacy: :closed
      team.update! name: "new-team"

      refute event = events.pop
    end

    test "instruments privacy change" do
      events = subscribe "team.change_privacy"
      team = create :team, organization: @org, privacy: :closed
      team.update! privacy: :secret

      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        note: "Team #{team}",
        team: team.to_s,
        team_id: team.id,
        org: @org.login,
        org_id: @org.id,
        privacy: "secret",
        privacy_was: "closed",
      }

      assert event = events.pop, "An event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments team destroy on self and all descendants" do
      team = create :team, organization: @org, privacy: :closed
      descendant_team = create :team, organization: @org, parent_team_id: team.id, privacy: :closed

      events = subscribe "team.destroy"

      expected_parent_payload = {
        ldap_mapped: team.ldap_mapped?,
        team: team.to_s,
        team_id: team.id,
        note: "Team #{team}",
        org: @org.login,
        org_id: @org.id,
      }

      expected_descendant_payload = {
        ldap_mapped: descendant_team.ldap_mapped?,
        team: descendant_team.to_s,
        team_id: descendant_team.id,
        note: "Team #{descendant_team}",
        org: @org.login,
        org_id: @org.id,
      }

      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
        team.destroy
      end

      assert event = events.pop, "an event was expected for the team"
      assert_equal expected_parent_payload, event.payload

      assert event = events.pop, "an event was expected for the descendant team"
      assert_equal expected_descendant_payload, event.payload
    end

    test "instruments adding repository to team" do
      permission = :pull
      events = subscribe "team.add_repository"
      expected_payload = {
        ldap_mapped: @team.ldap_mapped?,
        note: "Team #{@team}",
        permission: "read",
        team: @team.to_s,
        team_id: @team.id,
        org: @org.login,
        org_id: @org.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
      }

      @team.add_repository(@repo, permission)

      assert event = events.pop, "an event was expected"
      assert_equal "team.add_repository", event.name
      assert_equal expected_payload, event.payload
    end

    test "instruments update repo permissions between standard abilities" do
      actor = create :user
      GitHub.context.push(actor_id: actor.id)

      @team.add_repository @repo, :pull

      events = subscribe "team.update_repository_permission"
      expected_payload = {
        ldap_mapped: @team.ldap_mapped?,
        note: "Team #{@team}",
        id: "team.update_repository_permission.#{@repo.id}",
        new_repo_permission: "admin",
        new_repo_base_role: nil,
        old_repo_permission: "read",
        old_repo_base_role: nil,
        old_permissions: { pull: true, push: false, admin: false, triage: false, maintain: false },
        spammy: false,
        team_id: @team.id,
        actor_id: actor.id,
        team: @team.to_s,
        org: @org.login,
        org_id: @org.id,
        repo: @repo.name_with_owner,
        repo_id: @repo.id,
        public_repo: @repo.public?,
        actor: actor.login,
        user_id: actor.id,
        user: actor.login,
      }

      @team.update_repository_permission @repo, :admin

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments update repo permissions between custom roles" do
      create_custom_role(role_name: "old_custom_role", owner: @org_plus, base_role: :maintain)
      create_custom_role(role_name: "new_custom_role", owner: @org_plus, base_role: :read)
      actor = create :user
      GitHub.context.push(actor_id: actor.id)

      team = create :team, organization: @org_plus
      team.update_repository_permission @repo_plus, :old_custom_role

      events = subscribe "team.update_repository_permission"
      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        note: "Team #{team}",
        id: "team.update_repository_permission.#{@repo_plus.id}",
        new_repo_permission: "new_custom_role",
        new_repo_base_role: "read",
        old_repo_permission: "old_custom_role",
        old_repo_base_role: "maintain",
        old_permissions: { pull: true, push: true, admin: false, triage: true, maintain: true },
        spammy: false,
        team_id: team.id,
        actor_id: actor.id,
        team: team.to_s,
        org: @org_plus.login,
        org_id: @org_plus.id,
        repo: @repo_plus.name_with_owner,
        repo_id: @repo_plus.id,
        public_repo: @repo_plus.public?,
        actor: actor.login,
        user_id: actor.id,
        user: actor.login,
      }

      team.update_repository_permission @repo_plus, :new_custom_role, context: { old_permission: "old_custom_role", old_base_role: "maintain" }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments changing parent team on create" do
      events = subscribe "team.change_parent_team"

      team = create :team, organization: @org, name: "TeamA", privacy: :closed, parent_team_id: @parent_team.id

      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        team: team.to_s,
        team_id: team.id,
        note: "Team #{team}",
        org: @org.login,
        org_id: @org.id,
        parent_team: @parent_team.to_s,
        parent_team_id: @parent_team.id,
        parent_team_id_was: nil,
        parent_team_was: nil,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments changing parent team on update" do
      parent_team_was = create :team, organization: @org, privacy: :closed
      team = create :team, organization: @org,  privacy: :closed, parent_team_id: parent_team_was.id

      events = subscribe "team.change_parent_team"
      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        team: team.to_s,
        team_id: team.id,
        note: "Team #{team}",
        org: @org.login,
        org_id: @org.id,
        parent_team: @parent_team.to_s,
        parent_team_id: @parent_team.id,
        parent_team_id_was: parent_team_was.id,
        parent_team_was: parent_team_was.to_s,
      }

      team.parent_team = @parent_team

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      # reset to test update through setting parent_team_id
      team.parent_team = parent_team_was
      events.clear

      team.parent_team_id = @parent_team.id
      team.save

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments clearing parent team on update" do

      team = create :team, organization: @org,  privacy: :closed, parent_team_id: @parent_team.id

      events = subscribe "team.change_parent_team"
      expected_payload = {
        ldap_mapped: team.ldap_mapped?,
        team: team.to_s,
        team_id: team.id,
        note: "Team #{team}",
        org: @org.login,
        org_id: @org.id,
        parent_team: nil,
        parent_team_id: nil,
        parent_team_id_was: @parent_team.id,
        parent_team_was: @parent_team.to_s,
      }

      team.parent_team = nil

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload

      # reset to test update through setting parent_team_id
      team.parent_team = @parent_team
      events.clear

      team.parent_team_id = nil
      team.save

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "skips instrumentation on create when no parent is set" do
      events = subscribe "team.change_parent_team"

      create :team, organization: @org, name: "new-team", privacy: :closed

      assert_nil events.pop, "no event expected"
    end

    test "skips instrumentation on update to root team when parent is unchanged" do
      team = create :team, organization: @org, privacy: :closed, name: "root-team"

      events = subscribe "team.change_parent_team"

      team.update(name: "root-team-renamed")

      assert_nil events.pop, "no event expected"
    end

    test "skips instrumentation on update when parent team is unchanged" do
      events = subscribe "team.change_parent_team"

      @child_team.update(name: "child-team-renamed")

      assert_nil events.pop, "no event expected"
    end

    test "skips instrumentation on deleting a parent team" do
      events = subscribe "team.change_parent_team"
      assert_empty events

      @parent_team.destroy

      assert_nil events.pop, "no event expected"
    end
  end

  context "pending_invitations" do
    test "starts out empty" do
      assert @team.pending_invitations.empty?
      assert @team.team_invitations.empty?
    end

    test "isn't empty after inviting a user to the team" do
      @org.invite(@user, inviter: @org.admins.first, teams: [@team])

      assert_equal 1, @team.pending_invitations.size
      assert_equal 1, @team.team_invitations.size
    end

    test "is empty after the user accepts the only invitation to the team" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@team])
      invitation.accept

      assert_predicate @team.pending_invitations, :empty?
    end

    test "is empty after the user cancels the only invitation to the team" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@team])
      invitation.cancel(actor: @org.admins.first)

      assert_predicate @team.pending_invitations, :empty?
    end
  end

  context "pending_invitation_for" do
    test "is nil when there are no invitations for the user" do
      assert_nil @team.pending_invitation_for(@user)
    end

    test "is nil when all the invitations for the user are accepted" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@team])
      invitation.accept

      assert_nil @team.pending_invitation_for(@user)
    end

    test "is nil when there's a pending OrganizationInvitation on this team for another user" do
      invitee = create(:user, login: "invitee")
      invitation = @org.invite(invitee, inviter: @org.admins.first, teams: [@team])

      assert_nil @team.pending_invitation_for(@user)
    end

    test "is nil when there's a pending OrganizationInvitation on another team for the user" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@collabs_team])

      assert_nil @team.pending_invitation_for(@user)
    end

    test "returns an OrganizationInvitation when there's a pending one on just this team for the user" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@team])

      assert_equal invitation, @team.pending_invitation_for(@user)
    end

    test "returns an OrganizationInvitation when there's a pending one on this team and others for the user" do
      invitation = @org.invite(@user, inviter: @org.admins.first, teams: [@team, @collabs_team])

      assert_equal invitation, @team.pending_invitation_for(@user)
    end
  end

  context "membership_state_of" do
    test "is :pending when the user is invited" do
      @org.invite(@user, inviter: @org.admins.first, teams: [@team])

      assert_equal :pending, @team.membership_state_of(@user)
    end

    test "is :active when the user is a member" do
      @team.add_member(@user)

      assert_equal :active, @team.membership_state_of(@user)
    end

    test "is :inactive when the user is unaffiliated with the team" do
      assert_equal :inactive, @team.membership_state_of(@user)
    end

    test "is :inactive for child team membership by default" do
      @child_team.add_member(@user)

      assert_equal :inactive, @parent_team.membership_state_of(@user)
    end

    test "is :active for child team membership when immediate_only is false" do
      @child_team.add_member(@user)

      assert_equal :active, @parent_team.membership_state_of(@user, immediate_only: false)
    end
  end

  context "available_membership_action_for" do
    test "is :join when the user is not on the team" do
      #org admin
      assert_equal :join, @closed_team.available_membership_action_for(@owner)
    end

    test "is :leave when the user is on the team" do
      team_member = create(:user)
      @org.add_member(team_member)
      @closed_team.add_member(team_member)

      assert_equal :leave, @closed_team.available_membership_action_for(team_member)
    end

    test "is :request_membership when the user is unaffiliated with the team and not an org admin" do
      member_of_org = create(:user)
      @org.add_member(member_of_org)

      #normal member of the org
      assert_equal :request_membership, @closed_team.available_membership_action_for(member_of_org)
    end

    test "is :request_pending when the user is waiting to be admitted" do
      team_requester = create(:user)
      @org.add_member(team_requester)
      @closed_team.request_membership(team_requester)

      #member of the org with membership pending
      assert_equal :request_pending, @closed_team.available_membership_action_for(team_requester)
    end

    test "is :leave_disabled when the user is the only member and team is ldap mapped" do
      team_member = create(:user)
      @org.add_member(team_member)
      @closed_team.add_member(team_member)

      # team member when the only member
      @closed_team.members.delete_all
      @closed_team.add_member(team_member)
      Team.any_instance.expects(:ldap_mapped?).returns(true)
      assert_equal :leave_disabled, @closed_team.available_membership_action_for(team_member)
    end
  end

  context "sorted_visible_repositories_for" do
    test "for a nil user" do
      @team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      assert_same_elements [public_repo], @team.sorted_visible_repositories_for(nil)
    end

    test "for a user who isn't on the team" do
      @org.update_default_repository_permission(:none, actor: @owner)

      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team_without_direct_member = create(:team, organization: @org, name: "team-without-direct-member")
      team_with_direct_member    = create(:team, organization: @org, name: "team-with-direct-member")
      team_with_direct_member.add_member(direct_member)

      visible_private_repo = create(:private_repository, :minimal, owner: @org, name: "visible-private-repo")
      team_with_direct_member.add_repository(visible_private_repo, :pull)
      team_without_direct_member.add_repository(visible_private_repo, :pull)

      invisible_private_repo = create(:private_repository, :minimal, owner: @org, name: "invisible-private-repo")
      team_without_direct_member.add_repository(invisible_private_repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      team_without_direct_member.add_repository(public_repo, :pull)

      assert_same_elements [visible_private_repo, public_repo], team_without_direct_member.sorted_visible_repositories_for(direct_member)
    end

    test "for a user using auth via integration" do
      @org.update_default_repository_permission(:none, actor: @owner)

      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team_without_direct_member = create(:team, organization: @org, name: "team-without-direct-member")
      team_with_direct_member    = create(:team, organization: @org, name: "team-with-direct-member")
      team_with_direct_member.add_member(direct_member)

      visible_private_repo = create(:private_repository, :minimal, owner: @org, name: "visible-private-repo")
      team_with_direct_member.add_repository(visible_private_repo, :pull)
      team_without_direct_member.add_repository(visible_private_repo, :pull)

      invisible_private_repo = create(:private_repository, :minimal, owner: @org, name: "invisible-private-repo")
      team_without_direct_member.add_repository(invisible_private_repo, :pull)
      team_with_direct_member.add_repository(invisible_private_repo, :pull)

      installation = make_integration_installation(repositories: [visible_private_repo], permissions: { "members" => :read, "metadata" => :read })

      direct_member.oauth_access = installation.integration.grant(@owner)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      team_without_direct_member.add_repository(public_repo, :pull)

      assert_same_elements [visible_private_repo, public_repo], team_without_direct_member.sorted_visible_repositories_for(direct_member)
    end

    test "for a user using a v2 PAT with org access" do
      team_without_direct_member = create(:team, organization: @org, name: "team-without-direct-member")

      visible_private_repo = create(:private_repository, :minimal, owner: @org, name: "visible-private-repo")
      team_without_direct_member.add_repository(visible_private_repo, :pull)

      invisible_private_repo = create(:private_repository, :minimal, owner: @org, name: "invisible-private-repo")
      team_without_direct_member.add_repository(invisible_private_repo, :pull)

      access = create(:user_programmatic_access, owner: @owner)
      make_programmatic_access_grant(
        access: access, target: @org, actor: @owner,
        permissions: { "members" => :read, "metadata" => :read },
        repositories: [visible_private_repo], repository_selection: :subset,
      )

      @owner.programmatic_access = access

      # public repos are always accessible but not returned in the team's list if not explicitly added to the team
      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      assert_same_elements [visible_private_repo], team_without_direct_member.sorted_visible_repositories_for(@owner)
    end

    test "for an org owner who isn't on the team" do
      admin = create(:user, login: "org-admin")
      @org.add_admin(admin)

      private_repo = create(:private_repository, :minimal, owner: @org, name: "private-repo")
      @team.add_repository(private_repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      assert_same_elements [private_repo, public_repo], @team.sorted_visible_repositories_for(admin)
    end

    test "for a user who is on the team" do
      @team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      @org.add_member(@user)
      @team.add_member(@user)

      assert_same_elements [@repo, public_repo], @team.sorted_visible_repositories_for(@user)
    end

    test "inherited repositories for user who is on the team" do
      @parent_team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @parent_team.add_repository(public_repo, :pull)

      @org.add_member(@user)
      @child_team.add_member(@user)

      assert_same_elements [@repo, public_repo],
        @child_team.sorted_visible_repositories_for(@user, affiliation: :all)
    end

    test "sorts by action descending" do
      pull_repo = create(:private_repository, :minimal, owner: @org, name: "pull")
      admin_repo = create(:private_repository, :minimal, owner: @org, name: "admin")
      push_repo = create(:private_repository, :minimal, owner: @org, name: "push")
      @team.add_repository(pull_repo, :pull)
      @team.add_repository(admin_repo, :admin)
      @team.add_repository(push_repo, :push)

      @team.add_member(@user)

      assert_equal [admin_repo, push_repo, pull_repo],
        @team.sorted_visible_repositories_for(@user, sort: { field: "action", direction: "DESC" })
    end

    test "sorts by name ascending" do
      c_repo = create(:private_repository, :minimal, owner: @org, name: "c")
      a_repo = create(:private_repository, :minimal, owner: @org, name: "a")
      b_repo = create(:private_repository, :minimal, owner: @org, name: "b")
      @team.add_repository(c_repo, :pull)
      @team.add_repository(a_repo, :admin)
      @team.add_repository(b_repo, :push)

      @team.add_member(@user)

      assert_equal [a_repo, b_repo, c_repo],
        @team.sorted_visible_repositories_for(@user, sort: { field: "name", direction: "ASC" })
    end

    test "uses default sort if field and order are invalid" do
      c_repo = create(:private_repository, :minimal, owner: @org, name: "c")
      a_repo = create(:private_repository, :minimal, owner: @org, name: "a")
      b_repo = create(:private_repository, :minimal, owner: @org, name: "b")
      @team.add_repository(c_repo, :pull)
      @team.add_repository(a_repo, :admin)
      @team.add_repository(b_repo, :push)

      @team.add_member(@user)

      assert_equal [c_repo, a_repo, b_repo],
        @team.sorted_visible_repositories_for(@user, sort: { field: "not-valid", direction: "not-a-real-direction" })
    end

    if GitHub.enterprise?
      test "for a site admin who isn't in the org" do
        site_admin = create :staff_admin_user

        private_repo = create(:private_repository, :minimal, owner: @org, name: "private-repo")
        @team.add_repository(private_repo, :pull)

        public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
        @team.add_repository(public_repo, :pull)

        assert_same_elements [private_repo, public_repo], @team.sorted_visible_repositories_for(site_admin)
      end
    end
  end

  context "visible_repositories_for" do
    test "for a nil user" do
      @team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      assert_same_elements [public_repo], @team.visible_repositories_for(nil)
    end

    test "for a user who isn't on the team" do
      @org.update_default_repository_permission(:none, actor: @owner)

      direct_member = create(:user, login: "direct-member")
      @org.add_member(direct_member)

      team_without_direct_member = create(:team, organization: @org, name: "team-without-direct-member")
      team_with_direct_member    = create(:team, organization: @org, name: "team-with-direct-member")
      team_with_direct_member.add_member(direct_member)

      visible_private_repo = create(:private_repository, :minimal, owner: @org, name: "visible-private-repo")
      team_with_direct_member.add_repository(visible_private_repo, :pull)
      team_without_direct_member.add_repository(visible_private_repo, :pull)

      invisible_private_repo = create(:private_repository, :minimal, owner: @org, name: "invisible-private-repo")
      team_without_direct_member.add_repository(invisible_private_repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      team_without_direct_member.add_repository(public_repo, :pull)

      assert_same_elements [visible_private_repo, public_repo], team_without_direct_member.visible_repositories_for(direct_member)
    end

    test "for an org owner who isn't on the team" do
      admin = create(:user, login: "org-admin")
      @org.add_admin(admin)

      private_repo = create(:private_repository, :minimal, owner: @org, name: "private-repo")
      @team.add_repository(private_repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      assert_same_elements [private_repo, public_repo], @team.visible_repositories_for(admin)
    end

    test "for a user who is on the team" do
      @team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @team.add_repository(public_repo, :pull)

      @org.add_member(@user)
      @team.add_member(@user)

      assert_same_elements [@repo, public_repo], @team.visible_repositories_for(@user)
    end

    test "inherited repositories for user who is on the team" do
      @parent_team.add_repository(@repo, :pull)

      public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
      @parent_team.add_repository(public_repo, :pull)

      @org.add_member(@user)
      @child_team.add_member(@user)

      assert_same_elements [@repo, public_repo],
        @child_team.visible_repositories_for(@user, affiliation: :all)
    end

    if GitHub.enterprise?
      test "for a site admin who isn't in the org" do
        site_admin = create :staff_admin_user
        team = create :team, organization: @org

        private_repo = create(:private_repository, :minimal, owner: @org, name: "private-repo")
        team.add_repository(private_repo, :pull)

        public_repo = create(:public_repository, :minimal, owner: @org, name: "public-repo")
        team.add_repository(public_repo, :pull)

        assert_same_elements [private_repo, public_repo], team.visible_repositories_for(site_admin)
      end
    end
  end

  context "members_with_higher_access_to?" do
    test "is false if team's ability on repo is admin" do
      @team.add_repository(@repo, :admin)

      @org.add_member(@user)
      @team.add_member(@user)

      refute @team.members_with_higher_access_to?(@repo)
    end

    test "is false if team's ability on repo is write and no members have higher access" do
      @team.add_repository(@repo, :push)

      read_member  = create(:user, login: "read-member")
      write_member = create(:user, login: "write-member")
      @team.add_member(read_member)
      @team.add_member(write_member)

      refute @team.members_with_higher_access_to?(@repo)
    end

    test "is false if team's ability on repo is read and no members have higher access" do
      @team.add_repository(@repo, :pull)

      @org.add_member(@user)
      @team.add_member(@user)

      refute @team.members_with_higher_access_to?(@repo)
    end

    test "is true if team's ability on repo is read and a member has write access from another team" do
      @team.add_repository(@repo, :pull)

      @team.add_member(@user)

      write_team = create(:team, organization: @org, name: "write-team")
      write_team.add_repository(@repo, :push)
      write_team.add_member(@user)

      assert @team.members_with_higher_access_to?(@repo)
    end

    test "is true if team's ability on repo is write and a member has admin access from another team" do
      @team.add_repository(@repo, :push)

      @team.add_member(@user)

      admin_team = create(:team, organization: @org, name: "admin-team")
      admin_team.add_repository(@repo, :admin)
      admin_team.add_member(@user)

      assert @team.members_with_higher_access_to?(@repo)
    end

    test "is true if team's ability on repo is read and a member has write access as a collaborator" do
      @team.add_repository(@repo, :pull)

      @team.add_member(@user)
      @repo.add_member(@user, action: :write)

      assert @team.members_with_higher_access_to?(@repo)
    end

    test "is true if team's ability on repo is write and a member has admin access as a collaborator" do
      @team.add_repository(@repo, :push)

      @team.add_member(@user)
      @repo.add_member(@user, action: :admin)

      assert @team.members_with_higher_access_to?(@repo)
    end

    test "is true if team's ability on repo is write and a member is an org owner" do
      @team.add_repository(@repo, :push)
      @team.add_member(@owner)

      assert @team.members_with_higher_access_to?(@repo)
    end
  end

  context "#user_can_add_member" do
    test "returns true if the user is a team maintainer and the member is in the org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)
      @org.add_member(@team_maintainer)
      @team.add_member(@team_maintainer)
      @team.promote_maintainer(@team_maintainer)

      @org.add_member(@member)

      assert @team.user_can_add_member?(@member, actor: @team_maintainer)
    end

    test "returns true if the user is an org owner" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)
      assert @team.user_can_add_member?(@user, actor: @owner)
    end

    test "returns false if the adder is a team maintainer and the member is not in the org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @team = create :team, organization: @org
      @org.add_member(@team_maintainer)
      @team.add_member(@team_maintainer)
      @team.promote_maintainer(@team_maintainer)

      refute @team.user_can_add_member?(@member, actor: @team_maintainer)
    end

    test "returns false if the adder is neither a team maintainer nor an org owner" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)

      refute @team.user_can_add_member?(@member, actor: @user)
    end

    test "returns true if the adder can_have_granular_permissions" \
      "and may write organization members" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)
      adder = make_integration_installation(
        target: @org,
        permissions: { "members" => :write },
      )

      assert @team.user_can_add_member?(@member, actor: adder)
    end

    test "returns false if the adder can_have_granular_permissions" \
      "but may not write organization members" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)
      adder = make_integration_installation(
        target: @org,
        permissions: { "members" => :read },
      )

      refute @team.user_can_add_member?(@member, actor: adder)
    end
  end

  context "#actor_can_add_members?" do
    test "returns true if the user is a team maintainer and the member is in the org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)
      @org.add_member(@team_maintainer)
      @team.add_member(@team_maintainer)
      @team.promote_maintainer(@team_maintainer)

      @org.add_member(@member)

      assert @team.actor_can_add_members?([], actor: @team_maintainer)
    end

    test "returns true if the user is an org owner" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)
      assert @team.actor_can_add_members?([@user.id], actor: @owner)
    end

    test "returns false if the adder is a team maintainer and the member is not in the org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @team = create :team, organization: @org
      @org.add_member(@team_maintainer)
      @team.add_member(@team_maintainer)
      @team.promote_maintainer(@team_maintainer)

      refute @team.actor_can_add_members?([@member.id], actor: @team_maintainer)
    end

    test "returns false if the adder is neither a team maintainer nor an org owner" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)

      refute @team.actor_can_add_members?([], actor: @user)
    end

    test "returns true if the adder can_have_granular_permissions" \
      "and may write organization members" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)
      adder = make_integration_installation(
        target: @org,
        permissions: { "members" => :write },
      )

      assert @team.actor_can_add_members?([], actor: adder)
    end

    test "returns false if the adder can_have_granular_permissions" \
      "but may not write organization members" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member(@member)
      adder = make_integration_installation(
        target: @org,
        permissions: { "members" => :read },
      )

      refute @team.actor_can_add_members?([], actor: adder)
    end
  end

  context "visible_projects_for" do
    test "includes projects that are on the team and that the user has access to" do
      viewer = create(:user, login: "viewer")
      @org.add_member(viewer)

      @project.update_org_permission(nil)
      @project.update_user_permission(viewer, :read)

      @team.add_project(@project, :read)

      assert_same_elements [@project], @team.visible_projects_for(viewer)
    end

    test "excludes projects that are on the team but that the user does not have access to" do
      viewer = create(:user, login: "viewer")
      @org.add_member(viewer)

      @project.update_org_permission(nil)

      @team.add_project(@project, :read)

      assert_empty @team.visible_projects_for(viewer)
    end

    test "excludes projects that the user has access to but that are not on the team" do
      viewer = create(:user, login: "viewer")
      @org.add_member(viewer)

      @project.update_org_permission(nil)
      @project.update_user_permission(viewer, :read)

      assert_empty @team.visible_projects_for(viewer)
    end
  end

  context "#add_or_invite_member" do
    test "returns a dupe status if user is already a team member" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      inviter = create :user
      @org.add_member @user
      @org.add_member inviter
      @team.add_member inviter
      @team.add_member @user

      result = @team.add_or_invite_member(user: @user, inviter: inviter)
      assert_equal Team::AddMemberStatus::DUPE, result
    end

    test "returns success if org member is added to the team" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      @org.add_member @user

      result = @team.add_or_invite_member(user: @user, inviter: @owner)
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "returns a NO_SEAT error for a non-org member, if the org is at seat limit" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      inviter = create :user

      per_seat_org = create(:organization,
        plan: "business",
        admin: @owner,
        seats: 5,
      )
      4.times { per_seat_org.add_member(create :user) }

      team = create :team, organization: per_seat_org
      per_seat_org.add_member inviter
      team.add_member inviter

      result = team.add_or_invite_member(user: @user, inviter: inviter)
      assert_equal Team::AddMemberStatus::NO_SEAT, result
    end

    test "returns a PENDING_CYCLE_NO_SEAT error for a non-org member, if the orgs pending cycle is at seat limit" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      inviter = create :user

      per_seat_org = create(:organization,
        plan: "business",
        admin: @owner,
        seats: 7,
      )
      4.times { per_seat_org.add_member(create :user) }

      create :billing_pending_plan_change,
        user: per_seat_org,
        actor: per_seat_org,
        seats: 5

      team = create :team, organization: per_seat_org
      per_seat_org.add_member inviter
      team.add_member inviter

      result = team.add_or_invite_member(user: @user, inviter: inviter)
      assert_equal Team::AddMemberStatus::PENDING_CYCLE_NO_SEAT, result
    end

    test "returns an org invitation if the user is not in org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      inviter = create :user

      @org.add_member inviter, action: :admin
      @team.add_member inviter

      result = @team.add_or_invite_member(user: @user, inviter: inviter)
      assert_equal OrganizationInvitation, result.class
      assert_equal "member", result.invitation_source
    end

    test "returns false if an invalid attempt to create org invitation" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

      inviter = create :user

      @org.add_member inviter
      @team.add_member inviter
      other_org = create :organization

      result = @team.add_or_invite_member(user: other_org, inviter: inviter)
      assert_equal false, result
    end

    test "with invitations bypassed, does not create an invitation to the organization" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      assert_no_difference "OrganizationInvitation.count" do
        @team.add_or_invite_member(user: @user, inviter: @owner)
      end
    end

    test "with invitations bypassed, adds org member to the team" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member @user

      @team.add_or_invite_member(user: @user, inviter: @owner)
      assert @team.member?(@user), "Invited user should be added to the team"
    end

    test "with invitations bypassed, returns a Team::AddMemberStatus::SUCCESS result" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @org.add_member @user

      result = @team.add_or_invite_member(user: @user, inviter: @owner)
      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "with invitations bypassed, returns an error if trying to add an Organization to the team" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      invitee = create :organization

      result = @team.add_or_invite_member(user: invitee, inviter: @owner)
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    test "with invitations bypassed, returns an error if trying to add a bot to the team" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      invitee = create(:integration).bot

      result = @team.add_or_invite_member(user: invitee, inviter: @owner)
      assert_equal Team::AddMemberStatus::NOT_USER, result
    end

    test "with invitations bypassed, returns an error if the inviter doesn't have permission to invite" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      inviter = create :user
      @team.add_member inviter

      result = @team.add_or_invite_member(user: @user, inviter: inviter)
      assert result.error?
      assert_equal Team::AddMemberStatus::NO_PERMISSION, result
    end

    test "with invitations bypassed, adds non-org member to the org" do
      GitHub.stubs(:bypass_org_invites_enabled?).returns(true)

      @team.add_or_invite_member(user: @user, inviter: @owner)
      assert @org.member?(@user), "Invited user should be added to the organization"
    end

    test "invites business member when no licenses remain", skip_enterprise: true do
      inviter = create :user
      business = create :business, seats: 10
      other_org = create(:organization, admin: @user)

      only = [BusinessUserAccountCreateForOrganizationJob, AddToSearchIndexJob, BusinessOrganizationBillingJob, SyncOrganizationDefaultRepositoryPermissionJob, UpdateLockedRepositoriesJob, UpdatePrivateSearchOnEnterpriseOrgsJob]
      perform_enqueued_jobs(only: only) do
        business.add_organization(other_org)
        business.add_organization(@org)
      end

      @org.reload

      # Need to load a fresh business to avoid stale memoization
      business.update(seats: Business.find(business.id).consumed_enterprise_licenses)
      assert_equal 0, Business.find(business.id).available_invitable_licenses, "expected business to have no more remaining licenses"

      result = @team.add_or_invite_member(user: @user, inviter: inviter)

      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "add business member wihtout invite if direct member of business" do
      business = create :business
      other_org = create(:organization, admin: @user)

      only = [BusinessUserAccountCreateForOrganizationJob, AddToSearchIndexJob, BusinessOrganizationBillingJob, SyncOrganizationDefaultRepositoryPermissionJob, UpdateLockedRepositoriesJob, UpdatePrivateSearchOnEnterpriseOrgsJob]
      perform_enqueued_jobs(only: only) do
        business.add_organization(other_org)
        business.add_organization(@org)
      end

      @org.reload

      result = @team.add_or_invite_member(user: @user, inviter: @owner)

      assert_equal Team::AddMemberStatus::SUCCESS, result
    end

    test "add business member with invite when no saml sso", skip_with_all_emus: true, skip_enterprise: true do
      business = create :business
      other_org = create(:organization, admin: @user)

      only = [BusinessUserAccountCreateForOrganizationJob, AddToSearchIndexJob, BusinessOrganizationBillingJob, SyncOrganizationDefaultRepositoryPermissionJob, UpdateLockedRepositoriesJob, UpdatePrivateSearchOnEnterpriseOrgsJob]
      perform_enqueued_jobs(only: only) do
        business.add_organization(other_org)
        business.add_organization(@org)
      end

      @org.reload

      Organization.any_instance.stubs(:meets_sso_requirements?).returns(false)

      result = @team.add_or_invite_member(user: @user, inviter: @owner)

      assert_equal OrganizationInvitation, result.class
      assert_equal "member", result.invitation_source
    end

    test "invites email if there's a bundled license assignment even if there are no licenses remaining", skip_enterprise: true do
      email = "something@example.com"
      business = create(:business, :volume_licensed, seats: 1) # 1 seat for the admin of @org
      create(:licensing_bundled_license_assignment, business: business, email: email, user: nil)
      business.add_organization(@org)
      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
      @org.reload

      assert_equal 100, Business.find(business.id).available_invitable_licenses, "expected business to have remaining licenses"

      result = @team.add_or_invite_member(user: nil, inviter: @org.admins.first, email: email)

      assert_equal OrganizationInvitation, result.class
    end

    if GitHub.bypass_org_invites_enabled?
      test "returns success when adding org member by email" do
        @org.add_member(@user)
        @org.reload

        assert @org.member?(@user)

        result = @team.add_or_invite_member(user: nil, inviter: @owner, email: @user.email)

        assert_equal Team::AddMemberStatus::SUCCESS, result
      end

      test "returns success when adding business member by email" do
        other_org = create :organization, admin: @owner
        business = create :business, owners: [@owner], organizations: [@org, other_org]
        team = create :team, organization: other_org
        @org.add_member(@user)
        @org.reload
        other_org.reload

        assert_equal business, @org.business
        assert_equal business, other_org.business
        assert @org.member?(@user)
        refute other_org.member?(@user)

        result = team.add_or_invite_member(user: nil, inviter: @owner, email: @user.email)

        assert_equal Team::AddMemberStatus::SUCCESS, result
      end
    else
      test "returns success when adding org member by email regardless of licenses remaining" do
        team = create :team, organization: @org_plus
        @org_plus.update(seats: 2)
        @org_plus.add_member(@user)
        @org_plus.reload

        assert_nil @org_plus.business
        assert_predicate @org_plus, :at_seat_limit?
        assert @org_plus.member?(@user)

        result = team.add_or_invite_member(user: nil, inviter: @owner, email: @user.email)

        assert_equal Team::AddMemberStatus::SUCCESS, result
      end

      test "returns success when adding business member by email regardless of licenses remaining" do
        business = create :business, owners: [@owner], organizations: [@org], seats: 2
        other_org = create :organization, admin: @owner
        team = create :team, organization: other_org

        only = [BusinessUserAccountCreateForOrganizationJob, BusinessOrganizationBillingJob, BusinessUpdateLicenseUsageJob]
        perform_enqueued_jobs(only: only) do
          @org.add_member(@user)
          business.add_organization(other_org)
        end

        @org.reload
        other_org.reload

        assert_equal business, @org.business
        assert_equal business, other_org.business
        assert_predicate other_org, :at_seat_limit?
        assert @org.member?(@user)
        refute other_org.member?(@user)

        result = team.add_or_invite_member(user: nil, inviter: @owner, email: @user.email)

        assert_equal Team::AddMemberStatus::SUCCESS, result
      end
    end
  end

  context "Team.legacy_admin scope" do
    test "includes legacy admin teams" do
      legacy_admin_team = create(:team, organization: @org, permission: "admin")

      assert_same_elements [legacy_admin_team], @org.teams.legacy_admin
    end

    test "excludes regular teams" do
      assert_empty @org.teams.legacy_admin
    end

    test "excludes the legacy owners team" do
      create(:team, organization: @org, name: "Owners", permission: "admin")
      assert_empty @org.teams.legacy_admin
    end
  end

  context "legacy_admin?" do
    test "old admin teams become legacy_admin teams" do
      admin_team = create(:team, organization: @org, permission: "admin")
      assert_predicate admin_team, :legacy_admin?
    end

    test "new teams are not legacy_admin teams" do
      refute_predicate @team, :legacy_admin?
    end

    test "legacy owners team is not a legacy admin team" do
      legacy_owners_team = create(:team, organization: @org, name: "Owners", permission: "admin")
      assert_predicate legacy_owners_team, :legacy_owners?
      refute_predicate legacy_owners_team, :legacy_admin?
    end
  end

  context "migrate_legacy_admin" do
    test "stops legacy admin teams from being legacy admin teams anymore" do
      legacy_admin_team = create(:team, organization: @org, name: "legacy-admin-team", permission: "admin")
      assert_predicate legacy_admin_team, :legacy_admin?

      legacy_admin_team.migrate_legacy_admin
      legacy_admin_team.reload

      refute_predicate legacy_admin_team, :legacy_admin?
    end

    test "is a no-op on non-legacy-admin teams" do
      refute_predicate @team, :legacy_admin?

      @team.migrate_legacy_admin
      @team.reload

      refute_predicate @team, :legacy_admin?
    end
  end

  context "#members_scope" do
    test "returns immediate and child team members when membership is :all" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_same_elements [@member, @other_member, @child_team_member], @parent_team.members_scope(membership: :all)
      assert_same_elements [@member, @other_member, @child_team_member], @parent_team.members_scope
    end

    test "returns only immediate members when membership is :immediate" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_same_elements [@member, @other_member], @parent_team.members_scope(membership: :immediate)
    end

    test "returns child team members when membership is :child_team" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_same_elements [@child_team_member], @parent_team.members_scope(membership: :child_team)
    end
  end

  context "#members_scope_count" do
    test "returns count of immediate and child team members when membership is :all" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_equal 3, @parent_team.members_scope_count(membership: :all)
      assert_equal 3, @parent_team.members_scope_count
    end

    test "returns count of only immediate members when membership is :immediate" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_equal 2, @parent_team.members_scope_count(membership: :immediate)
    end

    test "returns count of child team members when membership is :child_team" do
      @org.add_member(@member)
      @org.add_member(@other_member)
      @org.add_member(@child_team_member)
      @parent_team.add_member @member
      @parent_team.add_member @other_member
      @child_team.add_member(@child_team_member)
      assert_equal 1, @parent_team.members_scope_count(membership: :child_team)
    end
  end

  context "#repositories_scope" do
    test "returns immediate and inherited repositories when affiliation is :all" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [inherited_repo, immediate_repo], @child_team.repositories_scope(affiliation: :all)
    end

    test "returns only immediate repositories when affialiation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [immediate_repo], @child_team.repositories_scope(affiliation: :immediate)
    end

    test "returns only inherited repositories when affialiation is :inherited" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [inherited_repo], @child_team.repositories_scope(affiliation: :inherited)
    end
  end

  context "self.repositories_scope" do
    test "raises error if team from different orgs" do
      other_org_team = create(:team, organization: create(:organization, plan: "bronze"))

      assert_raises ArgumentError do
        Team.repositories_scope(teams: [@team, other_org_team], affiliation: :all)
      end
    end

    test "returns results for multiple teams" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      other_repo = create :private_repository, :minimal, owner: @org
      other_team = create(:team, organization: @org, privacy: :closed)
      other_team.add_repository(other_repo, :pull)

      assert_same_elements [inherited_repo, immediate_repo, other_repo], Team.repositories_scope(teams: [@child_team, other_team], affiliation: :all)
    end

    test "returns immediate and inherited repositories when affiliation is :all" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [inherited_repo, immediate_repo], Team.repositories_scope(teams: [@child_team], affiliation: :all)
    end

    test "returns only immediate repositories when affialiation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [immediate_repo], Team.repositories_scope(teams: [@child_team], affiliation: :immediate)
    end

    test "returns only inherited repositories when affialiation is :inherited" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [inherited_repo], Team.repositories_scope(teams: [@child_team], affiliation: :inherited)
    end
  end

  context "#repositories_scope_count" do
    test "returns correct count of immediate and inherited repositories when affiliation is :all" do
      immediate_repo = create :private_repository, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      # Forks must not be counted
      perform_enqueued_jobs(only: [RepositoryAddTeamsJob, TeamAddForksJob]) do
        immediate_repo.fork(forker: @owner)
      end

      # Dupe abilities must not be counted
      @child_team.add_repository(inherited_repo, :pull)

      assert_equal 2, @child_team.repositories_scope_count
      assert_equal 2, @child_team.repositories_scope_count(affiliation: :all)
    end

    test "returns correct count of repositories when affiliation is :all and permission changed in child team" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :push)
      @child_team.add_repository(immediate_repo, :pull)
      @child_team.update_repository_permission(inherited_repo, :pull)

      assert_equal 2, @child_team.repositories_scope_count
      assert_equal 2, @child_team.repositories_scope_count(affiliation: :all)
    end

    test "returns correct count of immediate repositories when affiliation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal 1, @child_team.repositories_scope_count(affiliation: :immediate)
    end

    test "returns correct count of inherited repositories when affialiation is :inherited" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal 1, @child_team.repositories_scope_count(affiliation: :inherited)
    end
  end

  context "#direct_or_inherited_repo_ids" do
    test "returns immediate and inherited repo ids when affiliation is :all" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [inherited_repo.id, immediate_repo.id], @child_team.direct_or_inherited_repo_ids(affiliation: :all)
    end

    test "returns only immediate repo ids when affiliation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [immediate_repo.id], @child_team.direct_or_inherited_repo_ids(affiliation: :immediate)
    end

    test "can sort repo ids by action descending" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      inherited_repo2 = create :private_repository, owner: @org
      @child_team.add_repository(immediate_repo, :pull)
      @parent_team.add_repository(inherited_repo, :admin)
      @parent_team.add_repository(inherited_repo2, :push)

      assert_equal [inherited_repo.id, inherited_repo2.id, immediate_repo.id], @child_team.direct_or_inherited_repo_ids(sort: { action: :desc })
    end
  end

  context "self.direct_or_inherited_repo_ids" do
    test "raises error if team from different orgs" do
      other_org_team = create(:team, organization: create(:organization, plan: "bronze"))

      assert_raises ArgumentError do
        Team.direct_or_inherited_repo_ids(teams: [@team, other_org_team], affiliation: :all)
      end
    end

    test "returns results for multiple teams" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      other_repo = create :private_repository, :minimal, owner: @org
      other_team = create(:team, organization: @org, privacy: :closed)
      other_team.add_repository(other_repo, :pull)

      assert_same_elements [inherited_repo.id, immediate_repo.id, other_repo.id], Team.direct_or_inherited_repo_ids(teams: [@child_team, other_team], affiliation: :all)
    end

    test "returns immediate and inherited repo ids when affiliation is :all" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_same_elements [inherited_repo.id, immediate_repo.id], Team.direct_or_inherited_repo_ids(teams: [@child_team], affiliation: :all)
    end

    test "returns only immediate repo ids when affiliation is :immediate" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      @parent_team.add_repository(inherited_repo, :pull)
      @child_team.add_repository(immediate_repo, :pull)

      assert_equal [immediate_repo.id], Team.direct_or_inherited_repo_ids(teams: [@child_team], affiliation: :immediate)
    end

    test "can sort repo ids by action descending" do
      immediate_repo = create :private_repository, :minimal, owner: @org
      inherited_repo = create :private_repository, :minimal, owner: @org
      inherited_repo2 = create :private_repository, owner: @org
      @child_team.add_repository(immediate_repo, :pull)
      @parent_team.add_repository(inherited_repo, :admin)
      @parent_team.add_repository(inherited_repo2, :push)

      assert_equal [inherited_repo.id, inherited_repo2.id, immediate_repo.id], Team.direct_or_inherited_repo_ids(teams: [@child_team], sort: { action: :desc })
    end
  end

  context "#most_capable_inherited_ability_for_repo" do
    test "returns most capable inherited repo ability" do
      greatgrandparent_team = create(:team, organization: @org, privacy: :closed)
      grandparent_team = create(:team, organization: @org, privacy: :closed, parent_team_id: greatgrandparent_team.id)
      parent_team = create(:team, organization: @org, privacy: :closed, parent_team_id: grandparent_team.id)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)

      repo = create :private_repository, owner: @org
      parent_team.add_repository(repo, :pull)
      grandparent_team.add_repository(repo, :admin)
      greatgrandparent_team.add_repository(repo, :push)

      assert_equal grandparent_team, child_team.most_capable_inherited_ability_for_repo(repo).actor
    end

    test "doesn't return a team's direct abilities" do
      repo = create :private_repository, owner: @org
      @child_team.add_repository(repo, :admin)

      assert_nil @child_team.most_capable_inherited_ability_for_repo(repo)

      @parent_team.add_repository(repo, :pull)

      assert_equal @parent_team, @child_team.most_capable_inherited_ability_for_repo(repo).actor
    end
  end

  context "#allows_change_parent_requests_from?" do
    test "returns true if requesting team and new parent team are in the same org" do
      new_parent_team = create(:team, organization: @org, privacy: :closed)

      assert_equal true, new_parent_team.allows_change_parent_requests_from?(@child_team)
    end

    test "returns false if requesting team and new parent team are in different orgs" do
      new_org = create :organization, plan: "bronze", admin: @owner
      new_parent_team = create(:team, organization: new_org, privacy: :closed)

      assert_equal false, new_parent_team.allows_change_parent_requests_from?(@child_team)
    end
  end

  context "#add_forks_of" do
    test "active job is enqueued" do
      repo = create(:private_repository, owner: @org)
      assert_enqueued_with(job: TeamAddForksJob, args: [@team, repo]) do
        @team.add_forks_of(repo)
      end
    end

    test "does not lookup team repository ids for each fork" do
      @org.allow_private_repository_forking(actor: @org.admins.first)

      repo = create(:private_repository, owner: @org)
      @team.add_repository(repo, :pull)

      only = [RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) do
        3.times do
          user = create :user
          @team.add_member(user)
          user_fork = create(:fork_repository, forker: user, fork_repo: repo)
          @team.remove_repository_directly(user_fork)
        end
      end

      events = subscribe "ability.team.repository-ids"
      @team.add_forks_of!(repo)

      assert_equal 1, events.size
    end
  end

  context "#locally_managed?", team_synchronization_available: true do
    test "returns false if team has team sync enabled and existing group mappings" do
      tenant = create :team_sync_tenant
      org = tenant.organization
      team = create(:team, organization: org)
      create(:team_group_mapping, team: team, tenant: tenant)

      refute_predicate team, :locally_managed?
    end

    test "returns true if team has team sync enabled but no group mappings" do
      team = create :public_team, organization: create_org_with_team_sync

      assert_predicate team, :locally_managed?
    end

    test "returns false if team is enterprise_team_managed?", skip_enterprise: true do
      setup_enterprise_team
      assert_predicate @emu_team, :enterprise_team_managed?
      refute_predicate @emu_team, :locally_managed?
    end
  end

  context "#enterprise_team_managed?", skip_enterprise: true do
    test "returns true when a mapping exists" do
      setup_enterprise_team
      refute_nil EnterpriseTeamOrganizationMapping.where(enterprise_team: @enterprise_team).first
      assert_predicate @emu_team, :enterprise_team_managed?
    end

    test "returns false when a mapping doesn't exist" do
      setup_enterprise_team
      @enterprise_team_org_mapping.delete
      assert_nil EnterpriseTeamOrganizationMapping.where(enterprise_team: @enterprise_team).first
      @emu_team.reload
      refute_predicate @emu_team, :enterprise_team_managed?
    end

    test "returns false when enabled_for_organizations? is false" do
      setup_enterprise_team
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)
      refute_predicate @emu_team, :enterprise_team_managed?
    end
  end

  context "#externally_managed?", team_synchronization_available: true do
    test "returns false if team does not have team sync enabled" do
      @team.organization.disable_feature :team_sync

      refute_predicate @team, :externally_managed?
    end

    test "returns true if team has team sync enabled and existing group mappings" do
      tenant = create :team_sync_tenant
      org = tenant.organization
      team = create(:team, organization: org)
      create(:team_group_mapping, team: team, tenant: tenant)

      assert_predicate team, :externally_managed?
    end

    test "returns false if team has team sync enabled but no group mappings" do
      team = create :public_team, organization: create_org_with_team_sync

      refute_predicate team, :externally_managed?
    end

    test "return true if team has external group team" do
      external_group = create :external_group, :with_team
      assert_predicate external_group.external_group_teams.first.team, :externally_managed?
    end
  end

  context "#explicit_members?" do
    test "returns false for team without members" do
      team = create(:team, organization: @org, name: "explicit-members", slug: "explicit-members")
      refute_predicate team, :explicit_members?
    end

    test "returns true for team with members" do
      team = create(:team, organization: @org, name: "explicit-members", slug: "explicit-members")
      team.add_member(@member)
      assert_predicate team, :explicit_members?
    end
  end

  context "#async_externally_managed?", team_synchronization_available: true do
    test "returns a Promise of false if team does not have team sync enabled" do
      @team.organization.disable_feature :team_sync

      refute @team.async_externally_managed?.sync
    end

    test "returns a Promise of true if team has team sync enabled and existing group mappings" do
      tenant = create :team_sync_tenant
      org = tenant.organization
      team = create(:team, organization: org)
      create(:team_group_mapping, team: team, tenant: tenant)

      assert team.async_externally_managed?.sync
    end

    test "returns a Promise of false if team has team sync enabled but no group mappings" do
      team = create :public_team, organization: create_org_with_team_sync

      refute team.async_externally_managed?.sync
    end

    unless GitHub.single_business_environment?
      test "returns a Promise of true if group has external_group_team" do
        group_with_team = create :external_group, :with_team
        team = group_with_team.external_group_teams.first.team

        assert team.async_externally_managed?.sync
      end
    end
  end

  context "#async_locally_managed?", team_synchronization_available: true do
    test "returns a Promise of true if team does not have team sync enabled" do
      @team.organization.disable_feature :team_sync

      assert @team.async_locally_managed?.sync
    end

    test "returns a Promise of false if team is enterprise team managed" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      emu_admin = create :emu, :owner
      emu = emu_admin.enterprise_managed_business
      enterprise_team = create :enterprise_team, business: emu
      emu_org = create :organization, business: emu
      emu_org.add_member(emu_admin)
      emu_team = create :public_team, organization: emu_org
      enterprise_team_org_mapping = EnterpriseTeamOrganizationMapping.create!(enterprise_team: enterprise_team, organization: emu_org, team: emu_team)

      refute emu_team.async_locally_managed?.sync
    end unless GitHub.enterprise?

    test "returns a Promise of false if team has team sync enabled and existing group mappings" do
      tenant = create :team_sync_tenant
      org = tenant.organization
      team = create(:team, organization: org)
      create(:team_group_mapping, team: team, tenant: tenant)

      refute team.async_locally_managed?.sync
    end

    test "returns a Promise of true if team has team sync enabled but no group mappings" do
      team = create :public_team, organization: create_org_with_team_sync

      assert team.async_locally_managed?.sync
    end

    unless GitHub.single_business_environment?
      test "returns a Promise of false if group has external_group_team" do
        group_with_team = create :external_group, :with_team
        team = group_with_team.external_group_teams.first.team

        refute team.async_locally_managed?.sync
      end
    end
  end

  context "#can_be_externally_managed?", team_synchronization_available: true do
    test "returns false if team has child teams and org has team sync enabled" do
      org = create_org_with_team_sync
      team = create :public_team, organization: org
      create :public_team, parent_team: team, organization: org

      refute_predicate team, :can_be_externally_managed?
    end

    test "returns true if team doesn't have child teams and org has team sync enabled" do
      team = create :public_team, organization: create_org_with_team_sync

      assert_predicate team, :can_be_externally_managed?
    end

    test "returns false if team doesn't have child teams and org doesn't have team sync enabled" do
      @team.organization.disable_feature :team_sync

      refute_predicate @team, :can_be_externally_managed?
    end
  end

  context "#async_potential_child_teams" do
    test "should show visible teams as eligible, not including the requested team" do
      closed_team = create :team, organization:  @other_org, privacy: :closed
      other_team = create :team, organization: @other_org, privacy: :closed
      res = closed_team.async_potential_child_teams(viewer: @other_owner, query: nil).sync

      assert_same_elements [other_team], res
      assert_equal "ELIGIBLE", res.first.eligibility_status
    end

    test "should show secret teams as secret" do
      closed_team = create :team, organization:  @other_org, privacy: :closed
      secret_team = create :team, organization:  @other_org, privacy: :secret
      res = closed_team.async_potential_child_teams(viewer: @other_owner, query: nil).sync

      assert_same_elements [secret_team], res
      assert_equal "SECRET", res.first.eligibility_status
    end

    test "should show immediate children as children, grandchildren as eligible" do
      closed_team = create :team, organization:  @other_org, privacy: :closed
      child_team = create :team, organization: @other_org, parent_team_id: closed_team.id, privacy: :closed
      grandchild_team = create :team, organization: @other_org, parent_team_id: child_team.id, privacy: :closed
      res = closed_team.async_potential_child_teams(viewer: @other_owner, query: nil).sync

      assert_same_elements [child_team, grandchild_team], res
      assert_same_elements %w[CHILD ELIGIBLE], res.map(&:eligibility_status)
    end

    test "should show ancestors as ancestors" do
      closed_team = create :team, organization:  @other_org, privacy: :closed
      child_team = create :team, organization: @other_org, parent_team_id: closed_team.id, privacy: :closed
      res = child_team.async_potential_child_teams(viewer: @other_owner, query: nil).sync

      assert_same_elements ["ANCESTOR"], res.map(&:eligibility_status)
    end

    test "should show teams the viewer has no permission to as no_permission" do
      @other_org.add_member(@member)
      closed_team = create :team, organization:  @other_org, privacy: :closed
      other_team = create :team, organization: @other_org, privacy: :closed
      res = closed_team.async_potential_child_teams(viewer: @member, query: nil).sync

      assert_same_elements [other_team], res
      assert_same_elements ["PERMISSION"], res.map(&:eligibility_status)
    end

    test "should search based on name/slug" do
      closed_team = create :team, organization:  @other_org, privacy: :closed
      yay_team = create :team, organization: @other_org, privacy: :closed, name: "find me"
      create :team, organization: @other_org, privacy: :closed, name: "not going to be"
      res = closed_team.async_potential_child_teams(viewer: @other_owner, query: yay_team.name[1..6]).sync

      assert_same_elements [yay_team], res
      assert_same_elements ["ELIGIBLE"], res.map(&:eligibility_status)
    end

    test "does not show externally managed teams as potential child teams for EMUs", skip_enterprise: true do
      business = nil
      user = nil
      business = create :business, :enterprise_managed
      user = create :emu, business: business

      organization = create :enterprise_linked_organization, admin: user, business: business

      local_team = create :team, organization: organization, name: "local team", privacy: :closed
      another_local_team = create :team, organization: organization, name: "local team 2", privacy: :closed

      external_team = create :team, organization: organization, name: "external team", privacy: :closed
      external_group = create :external_group, :with_members, number_of_members: 2, business: business
      ExternalGroupTeam.create(external_group: external_group, team: external_team)

      another_external_team = create :team, organization: organization, name: "external team 2", privacy: :closed
      external_group = create :external_group, :with_members, number_of_members: 2, business: business
      ExternalGroupTeam.create(external_group: external_group, team: another_external_team)

      res = local_team.async_potential_child_teams(viewer: user, query: nil).sync

      assert_same_elements [another_local_team], res
      assert_same_elements ["ELIGIBLE"], res.map(&:eligibility_status)
    end
  end

  context "::search_name_and_slug" do
    test "returns teams matching the query" do
      query = @org_with_teams.teams.first.name[0..4]
      result = Team.search_name_and_slug(query: query, scope: @org_with_teams.teams)
      assert_same_elements @org_with_teams.teams, result
    end

    test "returns no teams if no teams matching the query are in scope" do
      query = "I should not ever match any team name"
      result = Team.search_name_and_slug(query: query, scope: @org_with_teams.teams)
      assert_same_elements [], result
    end

    test "returns the relation passed in when empty query passed in" do
      result = Team.search_name_and_slug(query: "", scope: @org_with_teams.teams)
      assert_same_elements @org_with_teams.teams, result
    end

    test "returns an empty relation when passed in an empty relation" do
      org_without_teams = create :organization, admin: @owner
      result = Team.search_name_and_slug(query: "team", scope: org_without_teams.teams)
      assert_same_elements [], result
    end
  end

  context "#ancestor_of?" do
    test "when passed in team is an ancestor, it returns true" do
      @child_team = create :public_team, organization: @org_with_teams, parent_team: @public_team
      assert @public_team.ancestor_of?(@child_team)
    end

    test "when passed in team is not an ancestor, it returns false" do
      @child_team = create :public_team, organization: @org_with_teams, parent_team: @public_team
      refute @child_team.ancestor_of?(@public_team)
    end
  end

  context ".batch_enqueue_update_repo_permissions" do
    test "enqueues 2 jobs to update the 2 teams based on the batch size of 1" do
      org = create :business_plus_organization
      repo = create :repository, owner: org
      member = create :user
      teams = [create(:team, organization: org), create(:team, organization: org)]
      teams.each do |team|
        team.add_member(member)
        repo.add_team(team, action: :write)
      end
      teams_repos = Ability.where(subject_type: "Repository", actor_type: "Team", action: :write, subject_id: repo.id)

      BatchUpdateTeamRepoPermissionsJob.expects(:perform_later).twice

      only = [BatchUpdateTeamRepoPermissionsJob]
      perform_enqueued_jobs(only: only) do
        Team.batch_enqueue_update_repo_permissions(teams_repos: teams_repos, actor_id: org.admin, action: :maintain, batch_size: 1)
      end
    end
  end

  context "#team_search_for_user" do
    test "default returns all descendants" do
      grandchild_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @child_team.id)

      query = TeamSearchQuery.new(nil)
      teams = @parent_team.team_search_for_user(query, @org.admin)

      assert_same_elements [@child_team, grandchild_team], teams
    end

    test "filters for all teams where user is a member" do
      user = create(:user)
      @org.add_member(user)
      @child_team.add_member(user)

      query = TeamSearchQuery.new("members:me")
      teams = @parent_team.team_search_for_user(query, user)

      assert_same_elements [@child_team], teams
    end

    test "filters for all empty teams" do
      user = create(:user)
      @org.add_member(user)

      query = TeamSearchQuery.new("members:empty")
      teams = @parent_team.team_search_for_user(query, user)

      assert_same_elements [@child_team], teams
    end

    test "filters by member query" do
      user = create(:user, login: "monalisa")
      @org.add_member(user)
      @child_team.add_member(user)

      query = TeamSearchQuery.new("@monalisa")
      teams = @parent_team.team_search_for_user(query, @org.admin)

      assert_same_elements [@child_team], teams
    end

    test "filters by query string" do
      syrup_team = create(:team, name: "Waffles with Syrup", organization: @org, privacy: :closed, parent_team_id: @parent_team.id)

      query = TeamSearchQuery.new("Syrup")
      teams = @parent_team.team_search_for_user(query, @org.admin)

      assert_same_elements [syrup_team], teams
    end

    test "immediate_only returns only returns immediate descendants" do
      grandchild_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @child_team.id)

      query = TeamSearchQuery.new(nil)
      teams = @parent_team.team_search_for_user(query, @org.admin, immediate_only: true)

      assert_same_elements [@child_team], teams
      refute_includes teams, grandchild_team
    end

    test "can filter by member and query string" do
      user = create(:user, login: "monalisa")
      syrup_team = create(:team, name: "Waffles with Syrup", organization: @org, privacy: :closed, parent_team_id: @parent_team.id)
      @org.add_member(user)
      syrup_team.add_member(user)

      query = TeamSearchQuery.new("Syrup @monalisa")
      teams = @parent_team.team_search_for_user(query, @org.admin)

      assert_same_elements [syrup_team], teams
    end
  end

  context "#can_be_child_of?" do
    test "returns false if team org and candidate parent team org are different" do
      parent_team = create :public_team
      other_team = create :public_team
      assert_equal \
        [false, "Team is in a different organization"],
        other_team.can_be_child_of?(parent_team)
    end

    test "returns false if candidate parent team is already direct parent of team" do
      parent_team = create :public_team
      child_team = create :public_team, organization: parent_team.organization, parent_team: parent_team
      assert_equal \
        [
          false,
          "#{parent_team.name} is already related to #{child_team.name} and cannot become a child team."
        ],
        child_team.can_be_child_of?(parent_team)
    end

    test "returns false if candidate parent team is already ancestor of team" do
      grandparent_team = create :public_team
      parent_team = create :public_team,
        organization: grandparent_team.organization,
        parent_team: grandparent_team
      child_team = create :public_team,
        organization: parent_team.organization,
        parent_team: parent_team
      assert_equal \
        [
          false,
          "#{grandparent_team.name} is already related to #{child_team.name} and cannot become a child team."
        ],
        child_team.can_be_child_of?(grandparent_team)
    end

    test "returns true when team can become child of candidate parent team" do
      parent_team = create :public_team
      child_team = create :public_team, organization: parent_team.organization
      assert_equal [true, nil], child_team.can_be_child_of?(parent_team)
    end

    test "should not allow a team to become a child of an enterprise-managed team" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org = create :organization
      parent_team = create :team, organization: org
      child_team = create :team, organization: org

      et = create :enterprise_team
      EnterpriseTeamOrganizationMapping.create(enterprise_team: et, organization: org, team: parent_team)

      result, message = child_team.can_be_child_of?(parent_team)

      assert_equal false, result
      assert_equal "Team is enterprise team managed and cannot become a child team.", message
    end
  end

  context "bulk_add_members" do
    test "allows changes to an enterprise managed team by the enterprise team", skip_enterprise: true do
      setup_enterprise_team
      @emu_team.bulk_add_members([@emu_admin], caller_type: :enterprise_team)
      assert_equal [@emu_admin.id], @emu_team.member_ids
    end

    test "does not call enterprise_team_managed? on an emu team", skip_enterprise: true do
      setup_enterprise_team
      Team.any_instance.expects(:enterprise_team_managed?).never

      @emu_team.bulk_add_members([@emu_admin], caller_type: :enterprise_team)
      assert_equal [@emu_admin.id], @emu_team.member_ids
    end

    test "does not call enterprise_team_managed? on a non-emu team" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      org = create :organization
      team = create :team, organization: org
      user = create :user
      et = create :enterprise_team
      org.add_member(user)
      EnterpriseTeamOrganizationMapping.create(enterprise_team: et, organization: org, team: team)

      Team.any_instance.expects(:enterprise_team_managed?).never

      team.bulk_add_members([user], caller_type: :enterprise_team)
      assert_equal [user.id], team.member_ids
    end

    test "does not auto subscribe users if called with :enterprise_team", skip_enterprise: true do
      Team.any_instance.expects(:auto_subscribe_user).never
      setup_enterprise_team
      @emu_team.bulk_add_members([@emu_admin], caller_type: :enterprise_team)
    end

    test "does not allow changes to an enterprise managed team by anything else", skip_enterprise: true do
      setup_enterprise_team
      @emu_team.add_member(@emu_admin)
      assert_empty @emu_team.member_ids
    end
  end

  context "#team_discussion_migration_in_progress?" do
    test "returns false if repository id not set" do
      @team.migration_complete = false
      @team.save

      refute @team.team_discussion_migration_in_progress?
    end

    test "returns false if migration marked as complete" do
      @team.repository_id = @repo.id
      @team.migration_complete = true
      @team.save

      refute @team.team_discussion_migration_in_progress?
    end

    test "returns true if all conditions are met" do
      @team.repository_id = @repo.id
      @team.migration_complete = false
      @team.save

      assert @team.team_discussion_migration_in_progress?
    end
  end

  test "#target_for_conditional_access returns the owning org" do
    team = create(:team)
    org = team.organization
    assert_equal org, team.target_for_conditional_access
  end

  context "#like_name scope" do
    test "correctly selects teams by name" do
      team1 = create :team, organization: @org, name: "team-query-me-1"
      team2 = create :team, organization: @org, name: "team-query-me-2"
      team3 = create :team, organization: @org, name: "team-not-me-1"
      team4 = create :team, organization: @org, name: "team-not-me-2"

      teams = Team.like_name("-query-")
      assert_same_elements [team1, team2], teams

      teams = Team.like_name("-not-")
      assert_same_elements [team3, team4], teams
    end
  end

  context "#order_by_name_asc scope" do
    test "correctly selects teams by name" do
      org = create :organization, plan: "bronze", admin: @owner

      create :team, organization: org, name: "z-team"
      create :team, organization: org, name: "a-team"
      create :team, organization: org, name: "k-team"
      create :team, organization: org, name: "b-team"

      teams = org.teams.order_by_name_asc.pluck(:name)
      assert_equal %w[a-team b-team k-team z-team], teams
    end
  end

  context "#with_no_parent scope" do
    test "correctly selects teams with no parents" do
      org = create :organization, plan: "bronze", admin: @owner

      parent_team = create :team, organization: org, name: "parent-team"
      grandparent_team = create :team, organization: org, name: "grandparent-team"
      standalone_team = create :team, organization: org, name: "standalone-team"
      child_team = create :team, organization: org, name: "child-team"

      child_team.update_attribute(:parent_team_id, parent_team.id)
      parent_team.update_attribute(:parent_team_id, grandparent_team.id)

      teams = org.teams.with_no_parent.pluck(:name)
      assert_equal %w[grandparent-team standalone-team], teams
    end
  end

  context "multiple_target_for_conditional_access" do
    test "computes TFCA for multiple teams" do
      teams = create_list(:team, 3)
      result = Team.multiple_target_for_conditional_access(teams)
      expected = teams.each_with_object({}) { |v, h| h[v] = v.target_for_conditional_access }
      assert_equal expected, result
    end

    test "raises if no teams are provided" do
      assert_raises ArgumentError do
        Team.multiple_target_for_conditional_access([@owner])
      end
      assert_raises ArgumentError do
        Team.multiple_target_for_conditional_access(Organization.all)
      end
    end
  end

  context "get team posts archive" do
    test "archive includes private posts if member is part of secret team" do
      secret_team = create(:team, organization: @org, privacy: :secret)
      secret_team.add_member(@user)

      secret_member = create(:user)
      secret_team.add_member(secret_member)

      @team_post1 = create(:discussion_post, team: secret_team, user: @user, private: true)
      @team_post2 = create(:discussion_post, team: secret_team, user: @user, private: true)
      @team_post3 = create(:discussion_post, team: secret_team, user: @user, private: true)

      assert_equal secret_team.get_team_posts_scope(secret_member).count, 3
    end

    test "archive does not include private posts if member is not part of secret team" do
      secret_team = create(:team, organization: @org, privacy: :secret)
      secret_team.add_member(@user)

      regular_member = create(:user)

      @team_post1 = create(:discussion_post, team: secret_team, user: @user, private: true)
      @team_post2 = create(:discussion_post, team: secret_team, user: @user, private: true)
      @team_post3 = create(:discussion_post, team: secret_team, user: @user, private: false)

      assert_equal secret_team.get_team_posts_scope(regular_member).count, 1
    end
  end
end

module TeamRemoveMemberOrgMembershipEntrySharedTests
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { TeamModelBaseTest }

  included do
    T.bind(self, T.class_of(TeamModelBaseTest))

    test "does_not_removes_derived_org_membership_entries_for_externally_managed_team" do
      assert @team_with_external_group.externally_managed?

      # since the team is externally managed the membership is not removed
      # because the external identity membership is still there
      assert_no_difference "OrganizationMembershipEntry.count" do
        @team_with_external_group.remove_member(@member)
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamUnlinkJob]
      end
    end

    test "removes_derived_org_membership_entries_for_externally_managed_team" do
      assert @team_with_external_group.externally_managed?

      assert @org.member?(@member)
      assert @org.member?(@org_member)

      # since the team is externally managed the membership is not removed
      # because the external identity membership is still there
      assert_difference "OrganizationMembershipEntry.count", -2 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamUnlinkJob] do
          @external_group_team.destroy
        end
      end

      refute @org.member?(@member)
      assert @org.member?(@org_member)
    end

    test "removes_derived_org_membership_entries_if_external_group_team_destroyed" do
      @external_group_team.destroy
      refute @team_with_external_group.externally_managed?

      assert @org.member?(@member)

      assert_difference "OrganizationMembershipEntry.count", -1 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamUnlinkJob] do
          @team_with_external_group.remove_member(@member)
        end
      end

      refute @org.member?(@member)
    end

    test "does_not_removes_explicit_org_membership_entries_if_external_group_team_destroyed" do
      @external_group_team.destroy
      refute @team_with_external_group.externally_managed?

      assert @org.member?(@org_member)

      assert_difference "OrganizationMembershipEntry.count", -1 do
        perform_enqueued_jobs only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob, ExternalGroupTeamUnlinkJob] do
          @team_with_external_group.remove_member(@org_member)
        end
      end

      assert @org.member?(@org_member)
    end

    test "cannot_remove_a_member_from_an_externally_managed_team" do
      assert @team_with_external_group.members.include?(@team_member)

      @team_with_external_group.remove_member @team_member, send_notification: false

      assert @team_with_external_group.members.include?(@team_member)
    end

    test "can_remove_a_member_from_an_externally_managed_team_when_an_identity_is_removed_from_external_group_members_with_reconcile_job" do
      GitHub.flipper[:disable_external_group_team_reconcile_job].disable
      assert @team_with_external_group.members.include?(@team_member)

      @external_group_with_members.external_identity_group_memberships.first.destroy
      ExternalGroupTeamReconcileJob.perform_now(external_group_id: @external_group_with_members.id, team_id: @external_group_with_members.external_group_teams.first.team_id, caller: self.class.name)
      refute @team_with_external_group.members.include?(@team_member)
    end

    test "members_are_removed_when_external_group_team_is_deleted" do
      assert @team_with_external_group.members.include?(@team_member)

      @external_group_team.destroy
      perform_enqueued_jobs only: ExternalGroupTeamUnlinkJob

      refute @team_with_external_group.members.include?(@team_member)
    end

    test "cannot_add_a_member_to_an_externally_managed_team_that_is_not_a_member_of_a_group" do
      refute @team_with_external_group.members.include?(@owner)

      @team_with_external_group.add_member(@owner)

      refute @team_with_external_group.members.include?(@owner)
    end

    test "returns_false_for_a_team_linked_to_an_external_group" do
      refute_predicate @team_with_external_group, :explicit_members?
    end

    test "scim_managed_enterprise_returns_true" do
      assert_predicate @team_with_external_group, :scim_managed_enterprise?
    end

    test "destroying_a_team_removes_the_external_group_team" do
      assert_difference ["ExternalGroupTeam.count", "Team.count"], -1 do
        perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) { @team_with_external_group.destroy }
      end
    end

    test "bulk_add_members_removes_org_membership" do
      GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not notify on org membership removal
      OrganizationMailer.expects(:removed_from_org).returns(stub(deliver_later: true)).at_least_once

      external_group = T.let(nil, T.untyped)
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
        external_group = create(:external_group, :with_members, :with_team, business: @business).reload
      end

      external_group_team = external_group.external_group_teams.first
      team = external_group_team.team
      org = team.organization
      member1 = team.members.first
      member2 = team.members.second
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        team.remove_member(member1, force: true)
        team.remove_member(member2, force: true)
        org.remove_member(member1)
        org.remove_member(member2)
      end

      refute org.member?(member1)
      refute org.member?(member2)
      refute_equal external_group.members.count, team.members.count

      team.destroy

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        assert_raises ActiveRecord::RecordNotFound do
          team.bulk_add_members([member1, member2])
        end
      end

      org_membership_entries = OrganizationMembershipEntry.where(organization_id: org.id, adder_id: team.id, user_id: [member1.id, member2.id])
      if GitHub.single_business_environment?
        # in single business environments, the org membership entries are not rolled back in the transaction,
        # so the org memberships are not removed either in the rescue
        refute_empty org_membership_entries
        assert org.member?(member1)
        assert org.member?(member2)
      else
        # the org membership entries are rolled back in the transaction,
        # so the org memberships are removed in the rescue
        assert_empty org_membership_entries
        refute org.member?(member1)
        refute org.member?(member2)
      end
    end

    test "bulk_add_members_leaves_existing_org_membership" do
      external_group = create(:external_group, :with_members, business: @business)
      member1 = external_group.members.first.external_identity.user
      member2 = external_group.members.second.external_identity.user

      # give member2 direct org membership first
      @org.add_member(member2)

      # set up the group/team connection
      team = create :team, organization: @org
      external_group_team = ExternalGroupTeam.create(external_group: external_group, team: team)
      perform_enqueued_jobs only: ExternalGroupTeamLinkJob

      # remove 2 members to create the mismatch
      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        team.remove_member(member1, force: true)
        team.remove_member(member2, force: true)
        @org.remove_member(member1)
      end

      # member1 is fully removed from team and org
      refute @org.member?(member1)
      refute team.member?(member1)

      # member2 is removed from team, but is not removed from org
      refute OrganizationMembershipEntry.where(organization_id: @org.id, adder_id: team.id, adder_type: :external_team, user_id: member2.id).any?
      assert_equal 1, OrganizationMembershipEntry.where(organization_id: @org.id, user_id: member2.id, adder_type: :admin).count
      assert @org.member?(member2)
      refute team.member?(member2)

      refute_equal external_group.members.count, team.members.count

      team.destroy

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        assert_raises ActiveRecord::RecordNotFound do
          team.bulk_add_members([member1, member2])
        end
      end

      derived_org_membership_entries = OrganizationMembershipEntry.where(organization_id: @org.id, adder_id: team.id, user_id: [member1.id, member2.id], adder_type: :external_team)
      if GitHub.single_business_environment?
        # in single business environments, the derived org membership entries are not rolled back in the transaction,
        # so the org memberships are not removed either in the rescue
        refute_empty derived_org_membership_entries
        assert @org.member?(member1)
      else
        # member1 and member2 do not have team backed org membership entry,
        # and member1 was not explicitly added to the org so the membership is removed
        assert_empty derived_org_membership_entries
        refute @org.member?(member1)
      end

      # member2 is still a member of the org and retains the explicit org membership entry
      assert_equal 1, OrganizationMembershipEntry.where(organization_id: @org.id, user_id: member2.id, adder_type: :admin).count
      assert @org.member?(member2)
    end
  end
end

class TeamModelBaseTest < GitHub::TestCase
end

class EMUTeamModelTest < TeamModelBaseTest
  skip_enterprise

  include TeamSyncTestHelper
  include TeamRemoveMemberOrgMembershipEntrySharedTests

  fixtures do
    @business = create :business, :enterprise_managed, seats: 10
    @owner = create :emu, :owner, business: @business
    @org = create :organization, business: @business, admin: @owner
    @org_without_team = create :organization, business: @business, admin: @owner

    @member = create :emu, business: @business
    @org_member = create :emu, business: @business
    @org.add_member @org_member

    @external_group_with_members = create :external_group, :with_members, business: @business, users: [@member, @org_member]
    @team_member = @external_group_with_members.external_identity_group_memberships.first.external_identity.user

    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @team_with_external_group = create :team, organization: @org
    @external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team_with_external_group)

    perform_enqueued_jobs only: ExternalGroupTeamLinkJob

    @unlinked_team = create :team, organization: @org
    @non_member = create :emu, business: @business

    @guest_collaborator = create :emu, :guest_collaborator, business: @business
  end

  test "returns success if emu organization user is added to the team" do
    GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

    @org.add_member @non_member
    assert @org.member?(@non_member), "Invited user should be added to the organization"

    result = @unlinked_team.add_or_invite_member(user: @non_member, inviter: @owner)
    assert_equal Team::AddMemberStatus::SUCCESS, result
    assert @unlinked_team.member?(@non_member), "Invited user should be added to the team"
  end

  test "returns success if emu enterprise user is added to the team" do
    GitHub.stubs(:bypass_org_invites_enabled?).returns(false)

    refute @org.member?(@non_member)

    result = @unlinked_team.add_or_invite_member(user: @non_member, inviter: @owner)
    assert_equal Team::AddMemberStatus::SUCCESS, result
    assert @unlinked_team.member?(@non_member), "Invited user should be added to the team"
    assert @org.member?(@non_member), "Invited user should be added to the organization"
  end

  test "team member is not added when all the licenses are used" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 10
    team = external_group_team.external_group_teams.first.team

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob
    result = team.add_member(@non_member)

    refute_predicate result, :success?
    assert_equal Team::AddMemberStatus::NO_SEAT, result
    refute team.member?(@non_member)
  end

  test "team members using bulk add are not added when all the licenses are used" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 10
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    result = team.bulk_add_members([@non_member, non_member2])

    refute_predicate result, :success?
    assert_equal Team::AddMemberStatus::NO_SEAT, result
    refute team.member?(@non_member)
    refute team.member?(non_member2)
  end

  test "none of the team members using bulk add are added when there are partial licenses left" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 6
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    assert team.organization.has_seat_for?(@non_member)

    result = team.bulk_add_members([@non_member, non_member2])

    refute_predicate result, :success?
    assert_equal Team::AddMemberStatus::NO_SEAT, result
    refute team.member?(@non_member)
    refute team.member?(non_member2)
  end

  test "no team members using bulk with failover does nothing" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 7
    team = external_group_team.external_group_teams.first.team

    result = T.let([], T.untyped)
    result = team.bulk_add_members_with_failover([])

    assert_empty result
  end

  test "none of the team members using bulk with failover are added when there are no licenses left" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 7
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    refute team.organization.has_seat_for?(@non_member)

    result = T.let([], T.untyped)
    assert_enqueued_jobs(0, only: BusinessUpdateLicenseUsageJob) do
      result = team.bulk_add_members_with_failover([@non_member, non_member2])
    end

    assert_equal Team::AddMemberStatus::NO_SEAT, result[0]
    assert_equal Team::AddMemberStatus::NO_SEAT, result[1]
    refute team.member?(@non_member)
    refute team.member?(non_member2)
  end

  test "one of the team members using bulk with failover is added when there are partial licenses left" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 6
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    assert team.organization.has_seat_for?(@non_member)

    result = T.let([], T.untyped)
    assert_enqueued_jobs(1, only: BusinessUpdateLicenseUsageJob) do
      result = team.bulk_add_members_with_failover([@non_member, non_member2])
    end

    assert_equal Team::AddMemberStatus::SUCCESS, result[0]
    assert_equal Team::AddMemberStatus::NO_SEAT, result[1]
    assert team.member?(@non_member)
    refute team.member?(non_member2)
  end

  test "team member of one team using bulk with failover is added to another team when no licenses left" do
    GitHub.flipper[:use_team_add_member_bulk_method].disable
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 7
    team = external_group_team.external_group_teams.first.team
    external_group_team2 = create :external_group, :with_members, :with_team, business: @business, organization: team.organization, users: [@non_member]

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    assert team.organization.has_seat_for?(@non_member)

    # Force the bulk add to fail so we fallback to the single mode addition
    Team.any_instance.stubs(:bulk_add_members).returns(Team::AddMemberStatus::NO_2FA)

    result = T.let([], T.untyped)
    assert_enqueued_jobs(0, only: BusinessUpdateLicenseUsageJob) do
      result = team.bulk_add_members_with_failover([@non_member])
    end

    assert_equal Team::AddMemberStatus::SUCCESS, result[0]
    assert team.member?(@non_member)
  end

  test "one of the team members using bulk with failover is added when there are partial licenses left and the other member is already a member of a team" do
    GitHub.flipper[:use_team_add_member_bulk_method].disable
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 5
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business
    external_group_team2 = create :external_group, :with_members, :with_team, business: @business, organization: team.organization, users: [non_member2]
    non_member3 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member3.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    assert team.organization.has_seat_for?(@non_member)
    assert team.organization.has_seat_for?(non_member2)

    # Force the bulk add to fail so we fallback to the single mode addition
    Team.any_instance.stubs(:bulk_add_members).returns(Team::AddMemberStatus::NO_2FA)

    result = T.let([], T.untyped)
    assert_enqueued_jobs(1, only: BusinessUpdateLicenseUsageJob) do
      result = team.bulk_add_members_with_failover([@non_member, non_member2, non_member3])
    end

    assert_equal Team::AddMemberStatus::SUCCESS, result[0]
    assert_equal Team::AddMemberStatus::SUCCESS, result[1]
    assert_equal Team::AddMemberStatus::NO_SEAT, result[2]
    assert team.member?(@non_member)
    assert team.member?(non_member2)
    refute team.member?(non_member3)
  end

  test "updates correct license count after team members are added using bulk with failover when there are partial licenses left" do
    external_group_team = create :external_group, :with_members, :with_team, business: @business, number_of_members: 6
    team = external_group_team.external_group_teams.first.team
    non_member2 = create :emu, business: @business
    non_member3 = create :emu, business: @business

    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: @non_member.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: external_group_team, external_identity: non_member2.external_identities.first)
    perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

    @business.update(seats: @business.seats + 1)
    consumed_enterprise_licenses = @business.reload.license_usage.consumed_enterprise_licenses

    assert team.organization.has_seat_for?(@non_member)

    result = T.let([], T.untyped)
    assert_enqueued_jobs(1, only: BusinessUpdateLicenseUsageJob) do
      result = team.bulk_add_members_with_failover([@non_member, non_member2, non_member3])
    end

    assert_equal Team::AddMemberStatus::SUCCESS, result[0]
    assert_equal Team::AddMemberStatus::SUCCESS, result[1]
    assert_equal Team::AddMemberStatus::NO_SEAT, result[2]
    assert team.member?(@non_member)
    assert team.member?(non_member2)
    refute team.member?(non_member3)
    assert_equal consumed_enterprise_licenses + 2, @business.reload.license_usage.consumed_enterprise_licenses
  end

  test "guest collaborators do get derived org membership through IdP-backed teams without being added to the org directly" do
    group_with_team = create :external_group, :with_team, business: @business

    team = group_with_team.external_group_teams.first.team
    org = team.organization

    ExternalIdentityGroupMembership.create(external_group: group_with_team, external_identity: @guest_collaborator.external_identities.first)
    ExternalIdentityGroupMembership.create(external_group: group_with_team, external_identity: @non_member.external_identities.first)

    team.add_member(@guest_collaborator)
    team.add_member(@non_member)

    assert org.member?(@guest_collaborator)
    assert org.member?(@non_member)
    assert team.member?(@guest_collaborator)
    assert team.member?(@non_member)
    assert_same_elements ["external_team"], OrganizationMembershipEntry.where(user_id: @guest_collaborator.id, organization_id: org.id).pluck(:adder_type)
    assert_empty OrganizationMembershipEntry.where(user_id: @guest_collaborator.id, organization_id: org.id, ability_id: -1)
    assert_empty OrganizationMembershipEntry.where(user_id: @non_member.id, organization_id: org.id, ability_id: -1)

    internal_team = create :team, organization: org
    internal_team.add_member(@guest_collaborator)

    assert_same_elements %w[external_team admin], OrganizationMembershipEntry.where(user_id: @guest_collaborator.id, organization_id: org.id).pluck(:adder_type)
    assert_same_elements ["external_team"], OrganizationMembershipEntry.where(user_id: @non_member.id, organization_id: org.id).pluck(:adder_type)
  end

  test "EMUs and guest collaborators get explicit org membership through non-IDP team membership" do
    team = create :team, organization: @org_without_team

    team.add_member(@non_member)
    team.add_member(@guest_collaborator)

    assert team.member?(@non_member)
    assert team.member?(@guest_collaborator)

    assert @org_without_team.member?(@non_member)
    refute_nil ability = @non_member.get_organization_ability(@org_without_team.id)
    assert OrganizationMembershipEntry.explicit?(user: @non_member, organization_id: @org_without_team.id, ability_id: ability.id)

    assert @org_without_team.member?(@guest_collaborator)
    refute_nil ability = @guest_collaborator.get_organization_ability(@org_without_team.id)
    assert OrganizationMembershipEntry.explicit?(user: @guest_collaborator, organization_id: @org_without_team.id, ability_id: ability.id)
  end

  test "guest collaborators are treated like normal users once they have org membership" do
    group_with_team = create :external_group, :with_team, business: @business

    externally_managed_team = group_with_team.external_group_teams.first.team
    org = externally_managed_team.organization

    ExternalIdentityGroupMembership.create(external_group: group_with_team, external_identity: @guest_collaborator.external_identities.first)

    internal_team = create :team, organization: org

    internal_repo = create :internal_repository, owner: org

    assert_same_elements [], org.reload.visible_repositories_for(@guest_collaborator)

    internal_team.add_member(@guest_collaborator)

    assert internal_team.member? @guest_collaborator
    assert org.member? @guest_collaborator

    refute_nil ability = @guest_collaborator.get_organization_ability(org.id)
    # the user would have been added as an explicit org member
    assert OrganizationMembershipEntry.explicit?(user: @guest_collaborator, organization_id: org.id, ability_id: ability.id)
    # there should be no derived records that exist
    refute OrganizationMembershipEntry.derived?(user: @guest_collaborator, organization_id: org.id, ability_id: ability.id)

    # user should have access to internal repos
    assert_same_elements [internal_repo], org.reload.visible_repositories_for(@guest_collaborator)

    externally_managed_team.add_member(@guest_collaborator)

    # the user should have a derived membership entry with their org ability created when they were added to the
    # second team since they already belonged to the org at that point.
    # if the user was not already a member, this record would be missing an ability
    assert OrganizationMembershipEntry.derived?(user: @guest_collaborator, organization_id: org.id, ability_id: ability.id)
  end

  test "removing an EMU from a non-IdP backed team does not remove their org membership" do
    team = create :team, organization: @org_without_team

    team.add_member(@non_member)
    team.add_member(@guest_collaborator)
    @org_without_team.add_member(@guest_collaborator)

    team.remove_member(@non_member)
    team.remove_member(@guest_collaborator)

    refute team.member?(@non_member)
    refute team.member?(@guest_collaborator)

    assert @org_without_team.member?(@non_member)
    refute_nil ability = @non_member.get_organization_ability(@org_without_team.id)
    assert OrganizationMembershipEntry.explicit?(user: @non_member, organization_id: @org_without_team.id, ability_id: ability.id)
    refute OrganizationMembershipEntry.derived?(user: @non_member, organization_id: @org_without_team.id, ability_id: ability.id)

    assert @org_without_team.member?(@guest_collaborator)
    refute_nil ability = @guest_collaborator.get_organization_ability(@org_without_team.id)
    assert OrganizationMembershipEntry.explicit?(user: @guest_collaborator, organization_id: @org_without_team.id, ability_id: ability.id)
    refute OrganizationMembershipEntry.derived?(user: @guest_collaborator, organization_id: @org_without_team.id, ability_id: ability.id)
  end
end

class GHESWithSCIMTeamModelTest < TeamModelBaseTest
  skip_unless :enterprise?

  include AuthenticationHelpers::SAML
  include TeamRemoveMemberOrgMembershipEntrySharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @business = create(:global_business)
    provider = @business.external_provider

    @owner = create :ghes_scim_user, business: @business
    @org = create :organization, business: @business, admin: @owner

    @member = create :ghes_scim_user, business: @business
    @org_member = create :ghes_scim_user, business: @business
    @org.add_member @org_member

    @external_group_with_members = create :external_group, :with_members, business: @business, users: [@member, @org_member]
    @team_member = @external_group_with_members.external_identity_group_memberships.first.external_identity.user

    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @team_with_external_group = create :team, organization: @org
    @external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team_with_external_group)

    perform_enqueued_jobs only: ExternalGroupTeamLinkJob
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end

  test "enterprise_server_scim_enabled? returns true" do
    assert_predicate @team_with_external_group, :enterprise_server_scim_enabled?
  end

  context "#add_member" do
    test "user without external identity (basic auth) can be added to team with GHES SCIM enabled" do
      team = create :team, organization: @org
      user = create :user, business: @business
      assert_empty user.external_identities

      team.add_member(user)

      assert team.member?(user)
    end
  end

  context "#bulk_add_members" do
    test "users without external identities (basic auth) can be added to teams with GHES SCIM enabled" do
      team = create :team, organization: @org
      user1 = create :user, business: @business
      user2 = create :user, business: @business
      assert_empty user1.external_identities
      assert_empty user2.external_identities

      team.bulk_add_members([user1, user2])

      assert team.member?(user1)
      assert team.member?(user2)
    end

    test "does not auto subscribe users if called with :enterprise_team" do
      Team.any_instance.expects(:auto_subscribe_user).never
      team = create :team, organization: @org
      user1 = create :user, business: @business
      user2 = create :user, business: @business

      team.bulk_add_members([user1, user2], caller_type: :enterprise_team)
    end
  end
end

class MultiTenantTeamModelTest < TeamModelBaseTest
  skip_enterprise

  setup do
    on_multi_tenant_enterprise
  end

  teardown do
    GitHub::CurrentTenant.remove
  end

  context "#tenant_slug_for_avatar" do
    test "returns company specific entity if `enterprise_managed_business` is nil" do
      org = make_trusted_oauth_apps_owner
      team = create(:team, organization: org)
      assert_equal GitHub.company_specific_entity_acronym, team.tenant_slug_for_avatar
    end

    test "return business slug if team belongs to tenant" do
      user = create :emu
      business = user.enterprise_managed_business
      GitHub::CurrentTenant.set(business)

      org = create(:organization)
      team = create(:team, organization: org)
      assert_equal org.business.slug, team.tenant_slug_for_avatar
    end
  end
end
