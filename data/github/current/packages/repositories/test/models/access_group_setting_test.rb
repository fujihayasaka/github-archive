# typed: true
# frozen_string_literal: true

require "test_helper"

class AccessGroupSettingTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @biz = Business.first || create(:business)
    @org = create(:organization, business: @biz, plan: "business_plus")

    @blue_team = create(:team, organization: @org, name: "blue")
    @green_team = create(:team, organization: @org, name: "green")
    @red_team = create(:team, organization: @org, name: "red")
    @yellow_team = create(:team, organization: @org, name: "yellow")

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org, group_path: "")
    @repo3 = create(:private_repository, owner: @org, group_path: "animals")
    @repo4 = create(:private_repository, owner: @org, group_path: "animals/dog")

    access = AccessGroupSetting.add(@org, "")
    access.add("read", @blue_team.id)
    access.save!

    access = AccessGroupSetting.add(@org, "animals")
    access.add("read", @red_team.id)
    access.add("write", @green_team.id)
    access.save!

    access = AccessGroupSetting.add(@org, "animals/dog")
    access.add("admin", @red_team.id)
    access.add("admin", @blue_team.id)
    access.deny_team_changes
    access.save!
  end

  test "role change" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "animals/dog")
    access = AccessGroupSetting.load_by_group(group)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(access).orchestrate(User.ghost)
    end

    expected = GitHub.flipper[:repos_groups].enabled? ? [["admin", @blue_team.id], ["write", @green_team.id], ["admin", @red_team.id]] : []
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo4.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual

    access = AccessGroupSetting.add(@org, "animals/dog")
    access.add("write", @red_team.id)
    access.save!
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(access).orchestrate(User.ghost)
    end

    expected = GitHub.flipper[:repos_groups].enabled? ? [["admin", @blue_team.id], ["write", @green_team.id], ["write", @red_team.id]] : []
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo4.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual
  end

  test "apply" do
    group = RepositoryGroup.find_by(owner: @org, group_path: "animals")
    setting = AccessGroupSetting.load_by_group(group)

    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      o = T.must(setting).orchestrate(User.ghost)
    end

    assert_same_elements [], @repo1.teams
    assert_same_elements [], @repo2.teams
    expected = GitHub.flipper[:repos_groups].enabled? ? [@blue_team, @green_team, @red_team] : []
    assert_same_elements expected, @repo3.teams
    assert_same_elements expected, @repo4.teams

    expected = GitHub.flipper[:repos_groups].enabled? ? [["read", @blue_team.id], ["write", @green_team.id], ["read", @red_team.id]] : []
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo3.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual

    expected = GitHub.flipper[:repos_groups].enabled? ? [["admin", @blue_team.id], ["write", @green_team.id], ["admin", @red_team.id]] : []
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo4.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual

    # attempt to add a team to a repo that denies it (when FF is enabled)
    @yellow_team.add_repository(@repo4, "write")
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo4.id).pluck(:action, :actor_id)
    expected = if GitHub.flipper[:repos_groups].enabled?
      [["admin", @blue_team.id], ["write", @green_team.id], ["admin", @red_team.id]]
    else
      [["write", @yellow_team.id]]
    end

    assert_same_elements expected, actual

    # attempt to add a team to a repo that allows it
    @yellow_team.add_repository(@repo3, "write")
    expected = GitHub.flipper[:repos_groups].enabled? ? [["read", @blue_team.id], ["write", @green_team.id], ["read", @red_team.id], ["write", @yellow_team.id]] : [["write", @yellow_team.id]]
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo3.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual

    # removing a non-protected team should work
    @repo3.remove_team(@yellow_team)
    expected = expected = GitHub.flipper[:repos_groups].enabled? ? [["read", @blue_team.id], ["write", @green_team.id], ["read", @red_team.id]] : []
    actual = Ability.where(actor_type: "Team", subject_type: "Repository", subject_id: @repo3.id).pluck(:action, :actor_id)
    assert_same_elements expected, actual
  end
end
