# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"
require "test_helpers/launch/runner_groups_helper"

class Actions::RunnerGroupTest < GitHub::TestCase
  include Launch::RunnerGroupsHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @enterprise = create :business
    @org = create :organization
    @precreated_default_group = Actions::RunnerGroup.new(id: 1, name: "Default Group", precreated: true)
    @precreated_group = Actions::RunnerGroup.new(id: 2, name: "Default Larger Runners", precreated: true)
    @inherited_group = Actions::RunnerGroup.new(id: 3, name: "Enterprise Group", owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id))
    @org_group = Actions::RunnerGroup.new(id: 4, name: "Org Group")
  end

  teardown do
    GitHub::MysqlInstrumenter.untrack!
    GitHub::MysqlInstrumenter.reset_stats
  end

  test "returns the correct default? value" do
    default_group = Actions::RunnerGroup.new(id: 1, name: "test-group", precreated: true)
    assert_equal true, default_group.default?
    assert_equal true, default_group.precreated?

    precreated_group = Actions::RunnerGroup.new(id: 2, name: "test-group", precreated: true)
    assert_equal false, precreated_group.default?
    assert_equal true, precreated_group.precreated?

    user_group = Actions::RunnerGroup.new(id: 3, name: "test-group")
    assert_equal false, user_group.default?
    assert_equal false, user_group.precreated?
  end

  context "#computed_allow_public" do
    test "when not inherited, returns its own value" do
      group = build(:runner_group, allow_public: false)
      refute group.computed_allow_public

      group = build(:runner_group, allow_public: true)
      assert group.computed_allow_public
    end

    test "when inherited, returns its own value AND'd with the parent value" do
      group = build(:runner_group, :inherited, allow_public: true, inherited_allow_public: true)
      assert group.computed_allow_public # true && true

      group = build(:runner_group, :inherited, allow_public: false, inherited_allow_public: true)
      refute group.computed_allow_public # true && false

      group = build(:runner_group, :inherited, allow_public: true, inherited_allow_public: false)
      refute group.computed_allow_public # true && false

      group = build(:runner_group, :inherited, allow_public: false, inherited_allow_public: false)
      refute group.computed_allow_public # false && false
    end
  end

  test "sorts default groups first" do
    runner_groups = [@org_group, @inherited_group, @precreated_default_group, @precreated_group].sort
    expected_groups = [@precreated_default_group, @precreated_group, @org_group, @inherited_group]

    assert_equal expected_groups, runner_groups
  end

  test "sorts inherited groups after non-inherited groups" do
    runner_groups = [@inherited_group, @org_group].sort

    assert_equal @org_group.name, runner_groups.first.name
    assert_equal @inherited_group.name, runner_groups.second.name
  end

  test "visibility_for returns all for private enterprise groups" do
    runner_group = Actions::RunnerGroup.new(
      id: 42,
      name: "Enterprise Runners",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_PRIVATE,
    )
    assert_equal :ALL, Actions::RunnerGroup.visibility_for(runner_group, @enterprise)
  end

  test "visibility_for returns all for private inherited groups" do
    runner_group = Actions::RunnerGroup.new(
      id: 42,
      name: "Enterprise Runners",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_PRIVATE,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )
    assert_equal :ALL, Actions::RunnerGroup.visibility_for(runner_group, @org)
  end

  test "for_entity for org" do
    runner_group_all = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group all",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: true,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
    )
    runner_group_private = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: false,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
    )

    mock_list_groups(owner: @org, response_status: 200, runner_groups: [runner_group_all, runner_group_private])

    assert_equal(
      [runner_group_all, runner_group_private].map(&:name),
      Actions::RunnerGroup.for_entity(@org).map(&:name),
    )
  end

  test "for_entity for repo" do
    repo = create(:private_repository, owner: @org)
    different_repo = create(:private_repository, owner: @org)

    deleted_repo = create(:private_repository, owner: @org)
    deleted_repo_global_id = deleted_repo.global_relay_id
    deleted_repo.remove(@org)

    runner_group_all = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group all",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: true,
    )
    runner_group_private = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: false,
    )
    runner_group_selected = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: false,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      ],
    )
    runner_group_selected_different_repo = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected different repo",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: false,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: different_repo.global_relay_id),
      ],
    )
    runner_group_selected_deleted_repo = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected deleted repo",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: false,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: deleted_repo_global_id),
      ],
    )
    runner_group_selected_nothing = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected nothing",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: false,
      selected_targets: [],
    )

    runner_groups = [
      runner_group_all,
      runner_group_private,
      runner_group_selected,
      runner_group_selected_different_repo,
      runner_group_selected_deleted_repo,
      runner_group_selected_nothing,
    ]
    mock_list_groups(owner: @org, response_status: 200, runner_groups:)

    assert_equal(
      [runner_group_all, runner_group_private, runner_group_selected].map(&:name),
      Actions::RunnerGroup.for_entity(repo).map(&:name)
    )
  end

  test "for_entity for repo propagates include_runners" do
    repo = create(:private_repository, owner: @org)

    mock_list_groups(owner: @org, response_status: 200, runner_groups: [])

    Actions::RunnerGroup.for_entity(repo, include_runners: true)
  end

  test "for_entity for repo propagates include_runner_scale_sets" do
    repo = create(:private_repository, owner: @org)

    mock_list_groups(owner: @org, response_status: 200, runner_groups: [])

    Actions::RunnerGroup.for_entity(repo, include_runner_scale_sets: true)
  end

  test "for_entity for public repo only includes groups with allow_public" do
    repo = create(:public_repository, owner: @org)
    org_runner_group_all_public = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "org runner group all public",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: true,
    )
    org_runner_group_all_private = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "org runner group all private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: false,
    )
    org_runner_group_selected_public = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "org runner group selected public",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: true,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      ],
    )
    org_runner_group_selected_private = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "org runner group selected private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      allow_public: false,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      ],
    )
    inherited_runner_group_all_public = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "inherited runner group all public",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: true,
      inherited_allow_public: true,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )
    inherited_runner_group_all_public_inherit_private = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "inherited runner group all private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: true,
      inherited_allow_public: false,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )
    inherited_runner_group_private_inherit_public = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "inherited runner group all private",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_ALL,
      allow_public: false,
      inherited_allow_public: true,
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )

    runner_groups = [
      org_runner_group_all_public,
      org_runner_group_all_private,
      org_runner_group_selected_public,
      org_runner_group_selected_private,
      inherited_runner_group_all_public,
      inherited_runner_group_all_public_inherit_private,
      inherited_runner_group_private_inherit_public,
    ]
    mock_list_groups(owner: @org, response_status: 200, runner_groups:)

    assert_equal(
      [org_runner_group_all_public, org_runner_group_selected_public, inherited_runner_group_all_public].map(&:name),
      Actions::RunnerGroup.for_entity(repo).map(&:name)
    )
  end

  def test_preloading_selected_targets_for_orgs
    @org.business = @enterprise
    repo = create(:public_repository, owner: @org)
    repo2 = create(:public_repository, owner: @org)
    repo3 = create(:public_repository, owner: @org)
    org2 = create :organization
    repo4 = create(:public_repository, owner: org2)

    enterprise_runner_group = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected 1",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
      ],
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )
    org_runner_group_1 = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 2,
      name: "runner group selected 2",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo2.global_relay_id),
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo3.global_relay_id),
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo4.global_relay_id),
      ],
    )
    org_runner_group_2 = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 3,
      name: "runner group selected 3",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo2.global_relay_id),
      ],
    )

    runner_groups = [
      enterprise_runner_group,
      org_runner_group_1,
      org_runner_group_2,
    ]
    mock_list_groups(owner: @org, response_status: 200, runner_groups:)

    GitHub::MysqlInstrumenter.reset_stats
    GitHub::MysqlInstrumenter.track!

    runner_groups = Actions::RunnerGroup.for_entity(@org).sort_by(&:id)

    assert_equal 1, filter_primary_queries(GitHub::MysqlInstrumenter.queries).count

    assert_equal(3, runner_groups.size)
    assert_equal([], runner_groups.first.selected_targets)
    assert_same_elements([repo, repo2, repo3], runner_groups.second.selected_targets)
    assert_same_elements([repo, repo2], runner_groups.third.selected_targets)
  end

  def test_preloading_selected_targets_for_enterprises
    @org.business = @enterprise
    org2 = create :organization

    enterprise_runner_group_1 = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 1,
      name: "runner group selected 1",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: org2.global_relay_id),
      ],
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )
    enterprise_runner_group_2 = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 2,
      name: "runner group selected 2",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: org2.global_relay_id),
      ],
      owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
    )

    runner_groups = [
      enterprise_runner_group_1,
      enterprise_runner_group_2,
    ]
    mock_list_groups(owner: @enterprise, response_status: 200, runner_groups:)

    GitHub::MysqlInstrumenter.reset_stats
    GitHub::MysqlInstrumenter.track!

    runner_groups = Actions::RunnerGroup.for_entity(@enterprise).sort_by(&:id)

    assert_equal 1, filter_primary_queries(GitHub::MysqlInstrumenter.queries).count

    assert_equal(2, runner_groups.size)
    assert_equal([@org], runner_groups.first.selected_targets)
    assert_equal([], runner_groups.second.selected_targets)
  end

  def test_load_entity_handles_deleted_selected_targets
    repo = create(:public_repository, owner: @org)
    repo.remove(@org)

    org_runner_group = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 2,
      name: "runner group selected 2",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      ],
    )

    mock_list_groups(owner: @org, response_status: 200, runner_groups: [org_runner_group])

    runner_groups = Actions::RunnerGroup.for_entity(@org)
    assert_equal(1, runner_groups.size)
    assert_equal([], runner_groups[0].selected_targets)
  end

  def test_get_loads_selected_targets
    repo = create(:public_repository, owner: @org)
    runner_group = GitHub::Launch::Services::Runnergroups::RunnerGroup.new(
      id: 2,
      name: "runner group selected",
      visibility: Launch::Twirp::RunnerGroupsClient::GROUP_VISIBILITY_SELECTED,
      selected_targets: [
        GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: repo.global_relay_id),
      ],
    )

    GitHub::Launch::Services::Runnergroups::RunnerGroupsClient
      .any_instance
      .expects(:get_group)
      .with(
        GitHub::Launch::Services::Runnergroups::GetGroupRequest.new(
          owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
          plan_owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
          group_id: 1,
          include_runners: false,
          is_enterprise_owner: false,
          exclude_elastic_runners: true,
        )
      )
      .returns(Twirp::ClientResp.new(
        data: GitHub::Launch::Services::Runnergroups::GetGroupResponse.new(
          runner_group: runner_group
        )
      ))

    runner_group = Actions::RunnerGroup.get(@org, id: 1)
    assert_equal([repo], runner_group.selected_targets)
  end
end
