# typed: true
# frozen_string_literal: true
require "test_helper"

class TeamParentChangeRepairAbilitiesOperationTest < GitHub::TestCase

  fixtures do
    @owner   = create(:user)
    @org     = create :organization, plan: "bronze", admin: @owner
    @aki     = create(:user, login: "aki")
    @brandon = create(:user, login: "brandon")
    @katrina = create(:user, login: "katrina")
  end

  setup do
    # Now we have this hierarchy
    #
    #              marketing - opensource
    #            /
    #  employees
    #            \
    #             engineering
    #
    @team_employees   = create :team, organization: @org, privacy: :closed, name: "employees"
    @team_engineering = create :team, organization: @org, privacy: :closed, name: "engineering", parent_team_id: @team_employees.id
    @team_marketing   = create :team, organization: @org, privacy: :closed, name: "marketing",   parent_team_id: @team_employees.id
    @team_opensource  = create :team, organization: @org, privacy: :closed, name: "opensource",  parent_team_id: @team_marketing.id

    @team_marketing.add_member  @aki
    @team_marketing.add_member  @brandon
    @team_opensource.add_member @brandon # Yeah, he is a direct member of both teams
    @team_opensource.add_member @katrina

    Team::ParentChange::Lock.new(org_id: @org.id).unlock_all!
  end

  def repair(org)
    Team::ParentChange::RepairAbilitiesOperation.new(org.id).execute
  end

  def assert_original_state
    refute_accessible(@aki, @team_opensource)
    assert_accessible(@aki, @team_marketing)
    assert_accessible(@aki, @team_employees)
    refute_accessible(@aki, @team_engineering)

    assert_accessible(@brandon, @team_opensource)
    assert_accessible(@brandon, @team_marketing)
    assert_accessible(@brandon, @team_employees)
    refute_accessible(@brandon, @team_engineering)

    assert_accessible(@katrina, @team_opensource)
    assert_accessible(@katrina, @team_marketing)
    assert_accessible(@katrina, @team_employees)
    refute_accessible(@katrina, @team_engineering)
  end

  test "permissions are as we want them to be initially" do
    assert_original_state
  end

  test "all indirect abilities are missing, and restored" do
    Ability.indirect.delete_all

    refute_accessible(@aki, @team_opensource)
    assert_accessible(@aki, @team_marketing)
    refute_accessible(@aki, @team_employees)
    refute_accessible(@aki, @team_engineering)

    assert_accessible(@brandon, @team_opensource)
    assert_accessible(@brandon, @team_marketing)
    refute_accessible(@brandon, @team_employees)
    refute_accessible(@brandon, @team_engineering)

    assert_accessible(@katrina, @team_opensource)
    refute_accessible(@katrina, @team_marketing)
    refute_accessible(@katrina, @team_employees)
    refute_accessible(@katrina, @team_engineering)

    repair @org

    assert_original_state
  end

  test "successfully restores all abilities when some are missing" do
    indirect_employees_team_abilities = Ability.indirect.where(
      subject_id: @team_employees.id,
      subject_type: @team_employees.ability_type,
    )
    indirect_employees_team_abilities.delete_all
    assert_empty indirect_employees_team_abilities

    repair @org

    assert_original_state
  end

  test "successfully restores all abilties when there are extra" do
    extra_indirect_ability = Ability.create!(subject_id: @team_engineering.id,
                                             subject_type: @team_engineering.ability_type,
                                             actor_id: @katrina.id,
                                             actor_type: @katrina.ability_type,
                                             priority: :indirect,
                                             action: :read)
    repair @org

    refute Ability.find_by(id: extra_indirect_ability.id)
    assert_original_state
  end

  test "fails if lock has been already acquired" do
    lock = Team::ParentChange::Lock.new(org_id: @org.id)
    lock.try_lock!

    assert_raises(Team::ParentChange::CannotAcquireLockError) do
      repair @org
    end
  end

  test "deletes PendingQueue if there were any" do
    @team_opensource.parent_team = @team_engineering
    assert Team::ParentChange::PendingQueue.new(org_id: @org.id).exist?

    repair @org

    refute Team::ParentChange::PendingQueue.new(org_id: @org.id).exist?
  end
end
