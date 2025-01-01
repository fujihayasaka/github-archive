# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamDestructionDestroyOperationTest < GitHub::TestCase
  include HookIntegrationTestHelper

  fixtures do
    @owner = create(:user)
    @org = create :organization, plan: "bronze", admin: @owner
    @org.update_default_repository_permission(:none, actor: @owner)

    @grand_parent_team = create(:team, organization: @org,
      privacy: :closed,
      name: "grand-parent-team")
    @parent_team = create(:team, organization: @org,
      privacy: :closed,
      parent_team_id: @grand_parent_team.id,
      name: "parent-team")
    @team = create(:team, organization: @org,
      privacy: :closed,
      parent_team_id: @parent_team.id,
      name: "team")
    @child_team = create(:team, organization: @org,
      privacy: :closed,
      parent_team_id: @team.id,
      name: "child-team")

    @direct_member = create(:user)
    @team.add_member(@direct_member)
    @indirect_member = create(:user)
    @child_team.add_member(@indirect_member)
    @member_ids = [@indirect_member, @direct_member].map(&:id)
    @ancestor_ids = [@indirect_member, @direct_member].map(&:id)
  end

  test "#execute destroys the teams in the hierarchy and enqueues a job for the dependants" do
    assert Team.exists?(@parent_team.id)
    assert Team.exists?(@team.id)
    assert Team.exists?(@grand_parent_team.id)

    expected_team_info = {
      @child_team.id.to_s => { name: @child_team.name, legacy_owners: @child_team.legacy_owners?, slug: @child_team.slug, ldap_mapped: false, enterprise_team_managed: false },
      @team.id.to_s => { name: @team.name, legacy_owners: @team.legacy_owners?, slug: @team.slug, ldap_mapped: false, enterprise_team_managed: false },
      @parent_team.id.to_s => { name: @parent_team.name, legacy_owners: @parent_team.legacy_owners?, slug: @parent_team.slug, ldap_mapped: false, enterprise_team_managed: false },
    }

    check_args = proc do |org_id, team_info, member_ids, grand_parents, _options|
      assert_equal [@org.id], org_id
      assert_equal expected_team_info, team_info
      assert_same_elements @member_ids, member_ids
      assert_equal [@grand_parent_team.id], grand_parents
    end

    assert_enqueued_with(job: DestroyTeamDependantsJob, args: check_args, queue: "destroy_team_dependants") do
      Team::Destruction::DestroyOperation.new(@parent_team).execute
    end

    refute Team.exists?(@parent_team.id)
    refute Team.exists?(@team.id)
    assert Team.exists?(@grand_parent_team.id)
  end

  test "does not throttle, as this is called in unicorn requests" do
    Team.expects(:throttle).never
    Team::Destruction::DestroyOperation.new(@parent_team).execute
  end

  test "a team is removed in the middle, but the operation completes normally" do
    assert Team.exists?(@parent_team.id)
    assert Team.exists?(@team.id)
    assert Team.exists?(@grand_parent_team.id)

    expected_team_info = {
      @child_team.id.to_s => { name: @child_team.name, legacy_owners: @child_team.legacy_owners?, slug: @child_team.slug, ldap_mapped: false, enterprise_team_managed: false },
      @parent_team.id.to_s => { name: @parent_team.name, legacy_owners: @parent_team.legacy_owners?, slug: @parent_team.slug, ldap_mapped: false, enterprise_team_managed: false },
    }

    check_args = proc do |org_id, team_info, member_ids, grand_parents, _options|
      assert_equal [@org.id], org_id
      assert_equal expected_team_info, team_info
      assert_same_elements @member_ids, member_ids
      assert_equal [@grand_parent_team.id], grand_parents
    end

    assert_enqueued_with(job: DestroyTeamDependantsJob, args: check_args, queue: "destroy_team_dependants") do
      operation = Team::Destruction::DestroyOperation.new(@parent_team)
      @team.delete
      operation.execute
    end

    refute Team.exists?(@parent_team.id)
    refute Team.exists?(@team.id)
    assert Team.exists?(@grand_parent_team.id)
  end

  test "two operations race" do
    team_community    = create :team, organization: @org, privacy: :closed, name: "community",  parent_team_id: @team.id
    operation         = Team::Destruction::DestroyOperation.new(@parent_team)
    another_operation = Team::Destruction::DestroyOperation.new(@team)

    # Deleting the parent team should also delete the team subject of another_operation
    operation.execute

    refute Team.exists?(@parent_team.id)
    refute Team.exists?(@team.id)
    refute Team.exists?(team_community.id)

    expected_team_info = {
      @team.id.to_s => { name: @team.name, legacy_owners: @team.legacy_owners?, slug: @team.slug, ldap_mapped: false },
    }

    check_args = proc do |org_id, team_info, member_ids, grand_parents, _options|
      assert_equal @org.id, org_id
      assert_equal expected_team_info, team_info
      assert_equal [], member_ids
      assert_same_elements [@parent_team.id, @grand_parent_team.id], grand_parents
    end

    # Deleting the parent team shouldn't do anything
    another_operation.execute
    assert_enqueued_with(job: DestroyTeamDependantsJob, queue: "destroy_team_dependants")
  end

  test "hooks succeed when child operation wins race against parent operation" do
    perform_enqueued_jobs only: [DeliverHookEventJob, EnqueueToHookshotJob] do
      operation = Team::Destruction::DestroyOperation.new(@team)
      parent_operation = Team::Destruction::DestroyOperation.new(@parent_team)
      deletion_hook = create(:hook, :org, installation_target: @org, events: %w(team))
      deliveries = subscribe_to_hook_delivery("team")

      # Simulate race condition by ensuring query on parent always returns descendants.
      @parent_team.stubs(:descendants_depth_first).returns([@child_team, @team])

      operation.execute
      refute [@team, @child_team].any? { |t| Team.exists?(t.id) }
      assert Team.exists?(@parent_team.id)

      # Operation on parent team should not raise an exception.
      parent_operation.execute
      refute [@parent_team, @team, @child_team].any? { |t| Team.exists?(t.id) }

      deletion_payloads = deliveries
                            .all_payloads_for_hook(deletion_hook)
                            .find_all { |p| p[:action] == "deleted" }
      deletion_payload_team_ids = deletion_payloads
                                    .map { |p| p[:team] && p[:team][:id] }
                                    .sort

      assert_equal 3, deletion_payloads.length
      assert_equal(
        [@parent_team, @team, @child_team].map(&:id).sort,
        deletion_payload_team_ids)
    end
  end
end

# HookIntegrationTestHelper is included in the test above, which inlines all jobs
class TeamDestructionDestroyOperationWithoutHookIntegrationHelperTest < GitHub::TestCase
  test "enqueues job to clear team group mappings if team has no child teams and is mapped" do
    team = create(:team)
    create(:team_group_mapping, team: team)
    operation = Team::Destruction::DestroyOperation.new(team)
    job_args = [team.organization.global_relay_id, team.global_relay_id]

    assert_enqueued_with(job: ClearTeamGroupMappingsJob, args: job_args) do
      operation.execute
    end
  end

  test "doesn't enqueue job to clear team group mappings if team is not mapped" do
    team = create(:team)
    operation = Team::Destruction::DestroyOperation.new(team)

    assert_no_enqueued_jobs(only: ClearTeamGroupMappingsJob) do
      operation.execute
    end
  end

  test "enqueues job to clear team group mappings for child team if it is mapped and has no child teams" do
    parent_team = create(:public_team)
    child_team = create(:public_team, organization: parent_team.organization, parent_team_id: parent_team.id)
    create(:team_group_mapping, team: child_team)
    operation = Team::Destruction::DestroyOperation.new(parent_team)

    job_args = [child_team.organization.global_relay_id, child_team.global_relay_id]

    assert_enqueued_with(job: ClearTeamGroupMappingsJob, args: job_args) do
      operation.execute
    end
  end
end

module TeamDestructionDestroyOperationSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def test_execute_destroys_external_group_team
    assert_difference "ExternalGroupTeam.count", -1 do
      perform_enqueued_jobs only: DestroyTeamDependantsJob do
        Team::Destruction::DestroyOperation.new(@team_with_external_group).execute
      end
    end
  end

  def test_execute_enqueues_destroy_dependants_job_for_business_team
    BusinessTeam.stubs(:enabled_for_enterprise?).returns(true)
    org2 = create :organization, business: @business, admin: @emu
    business_team = create :business_team, business: @business, orgs: [@org_with_business, org2]

    team_info = Team::Destruction::DestroyOperation.team_info_for_dependants_destruction([business_team])
    org_ids = business_team.organization_ids
    member_ids = Team.members_of(business_team.id, immediate_only: false).pluck(:id)
    ancestor_ids = business_team.ancestor_ids

    assert_enqueued_with(job: DestroyTeamDependantsJob, args: [org_ids, team_info.slice(business_team.id.to_s), member_ids, ancestor_ids, { business: @business }]) do
      Team::Destruction::DestroyOperation.new(business_team).execute
    end
  end

  def test_execute_destroys_dependants_job_for_business_team
    BusinessTeam.stubs(:enabled_for_enterprise?).returns(true)
    org2 = create :organization, business: @business, admin: @emu

    external_group_with_members = create :external_group, :with_members, business: @business, number_of_members: 2
    external_group_users = external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    team_with_external_group = create :business_team, orgs: [@org_with_business, org2], business: @business
    external_group_team = ExternalGroupTeam.create!(external_group: external_group_with_members, team: team_with_external_group)

    assert_difference "ExternalGroupTeam.count", -1 do
      perform_enqueued_jobs only: DestroyTeamDependantsJob do
        Team::Destruction::DestroyOperation.new(team_with_external_group).execute
      end
    end
  end
end

class EMUTeamDestructionDestroyOperationTest < GitHub::TestCase
  include TeamDestructionDestroyOperationSharedTests

  fixtures do
    @emu = create :emu
    @business = @emu.enterprise_managed_business
    @org_with_business = create :organization, business: @business, admin: @emu

    @external_group_with_members = create :external_group, :with_members, business: @business, number_of_members: 2
    @external_group_users = @external_group_with_members.external_identity_group_memberships.map(&:external_identity).map(&:user)

    @team_with_external_group = create :team, organization: @org_with_business
    @external_group_team = ExternalGroupTeam.create(external_group: @external_group_with_members, team: @team_with_external_group)
  end
end unless GitHub.single_business_environment?
