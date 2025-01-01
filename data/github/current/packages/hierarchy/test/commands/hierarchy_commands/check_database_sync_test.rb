# typed: true
# frozen_string_literal: true

require "test_helper"

class HierarchyCommands::CheckDatabaseSyncTest < GitHub::TestCase
  include IssuesGraphTestHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  fixtures do
    @owner = create(:verified_user)
    @org = create(:organization, admin: @owner, plan: "business")
    @repo = create(:repository, owner: @org)

    @child_issue = create(:issue, repository: @repo)
    body = %Q(
    ```[tasklist]
    - [ ] #{@child_issue.url}
    ```
    )
    @parent_issue = create(:issue, repository: @repo, body: body)
  end

  setup do
    enable_feature_flag(:tasklist_block_sync_check)
  end

  test "requires the flag be enabled" do
    disable_feature_flag(:tasklist_block_sync_check)
    tlb = TasklistBlocks::TasklistBlock.new
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: nil
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    refute_dogstats_increment(stats_key)
  end

  test "it stats when there are no tasklists" do
    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      1,
      stats_key,
      tags: [
        "synced:true",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "outcome:#{HierarchyCommands::CheckDatabaseSync::NO_TASKLISTS}",
      ],
    )
  end

  test "it stats when there are no issues graph tasklists" do
    tlb = TasklistBlocks::TasklistBlock.new
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: nil
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      1,
      stats_key,
      tags: [
        "synced:false",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "sync_error:#{HierarchyCommands::CheckDatabaseSync::MISSING_DATA}_issues_graph",
      ],
    )
  end

  test "it logs when there are no issues graph tasklists" do
    tlb = TasklistBlocks::TasklistBlock.new
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: nil
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    expected = {
      "code.namespace": klass.name,
      "code.function": "call",
      "gh.catalog_service": "github/issues-graph",
      "gh.repository_id": @repo.id,
      "gh.issue_id": @parent_issue.id,
      "gh.issues_graph.pipeline_strategy": instance.pipeline_strategy,
      "gh.user_id": @owner.id,
      "gh.issues_graph.sync_error": HierarchyCommands::CheckDatabaseSync::MISSING_DATA + "_issues_graph",
      "Body": "issue hierarchy not synced",
    }
    assert_logged(**expected) do
      instance.call
    end
  end

  test "it handles discrepancies across the contents of multiple tasklist blocks" do
    mysql_tlb = TasklistBlocks::TasklistBlock.new(
      items: [
        TasklistBlocks::IssueReference.new(issue: @child_issue),
      ]
    )
    mysql_tlb_two = TasklistBlocks::TasklistBlock.new(
      items: [
        TasklistBlocks::IssueReference.new(issue: @child_issue),
      ]
    )
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([mysql_tlb, mysql_tlb_two]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: [
          build_proto_tasklist_block(issues: to_proto_issue(@child_issue)),
          build_proto_tasklist_block(issues: build_proto_issue),
        ]
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      stats_key,
      tags: [
        "synced:false",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "sync_error:#{HierarchyCommands::CheckDatabaseSync::MISMATCHED_TLI_DATA}",
      ],
    )
  end

  test "it handles discrepancies across the count of multiple tasklist blocks" do
    mysql_tlb = TasklistBlocks::TasklistBlock.new(
      items: [
        TasklistBlocks::IssueReference.new(issue: @child_issue),
      ]
    )
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([mysql_tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: [
          build_proto_tasklist_block(issues: to_proto_issue(@child_issue)),
          build_proto_tasklist_block,
        ]
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      stats_key,
      tags: [
        "synced:false",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "sync_error:#{HierarchyCommands::CheckDatabaseSync::MISMATCHED_TLB_COUNT}",
      ],
    )
  end

  test "it stats when there is an item-level discrepancy" do
    mysql_tlb = TasklistBlocks::TasklistBlock.new(
      items: [
        TasklistBlocks::IssueReference.new(issue: @child_issue),
      ]
    )
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([mysql_tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: build_proto_tasklist_block(issues: build_proto_issue),
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      stats_key,
      tags: [
        "synced:false",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "sync_error:#{HierarchyCommands::CheckDatabaseSync::MISMATCHED_TLI_DATA}",
      ],
    )
  end

  test "it stats when there is an item-level count discrepancy" do
    mysql_tlb = TasklistBlocks::TasklistBlock.new(
      items: [
        TasklistBlocks::IssueReference.new(issue: @child_issue),
        TrackingBlocks::DraftIssue.new(draft_issue: "I'm a draft", owner_id: @owner.id),
      ]
    )
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([mysql_tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: build_proto_tasklist_block(issues: to_proto_issue(@child_issue)),
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      stats_key,
      tags: [
        "synced:false",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "sync_error:#{HierarchyCommands::CheckDatabaseSync::MISMATCHED_TLI_COUNT}",
      ],
    )
  end

  test "it stats when there is no discrepancy" do
    mysql_tlb = TasklistBlocks::TasklistBlock.new(
      items: [TasklistBlocks::IssueReference.new(issue: @child_issue)]
    )
    @parent_issue.stubs(:body_result).returns(Struct.new(:tasklist_blocks).new([mysql_tlb]))
    stub_issue_hierarchy(
      issue: @parent_issue,
      result: build_get_issue_success_response(
        tracking: build_proto_tasklist_block(issues: to_proto_issue(@child_issue)),
      )
    )

    instance = klass.new(issue: @parent_issue, repository: @repo, viewer: @owner)
    instance.call
    assert_dogstats_increment(
      stats_key,
      tags: [
        "synced:true",
        "pipeline_strategy:#{instance.pipeline_strategy}",
        "outcome:#{HierarchyCommands::CheckDatabaseSync::DATA_IN_SYNC}",
      ],
    )
  end

  private def klass
    HierarchyCommands::CheckDatabaseSync
  end

  private def stats_key
    HierarchyCommands::CheckDatabaseSync::STATS_KEY_SYNCED
  end
end
