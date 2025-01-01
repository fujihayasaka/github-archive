# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::DiffChangesTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @actor = create(:verified_user)
    tasklist_body = <<~MD
    ```[tasklist]
    ### title
    - [ ] item 1
    ```
    MD
    @issue = create(:issue, body: tasklist_body, user: @actor)
  end

  context "happy path" do
    test "logs and returns success result when adding tasklist items" do
      expected = instrumentation_default.merge(
        tasklist_block_diff: 1,
        tasklist_item_diff: 1,
      )
      block = TasklistBlocks::TasklistBlock.new(items: [TrackingBlocks::DraftIssue.new(draft_issue: "foo", owner_id: @actor.id)])

      @result = klass.new(
        tasklist_blocks_previous: [],
        tasklist_blocks_next: [block],
        issue: @issue,
        actor: @actor,
      ).call

      assert_hydro_published(expected, schema: "github.v1.TasklistDiff")
      assert_predicate @result, :success?
    end

    test "logs and returns success result when adding tasklist blocks" do
      expected = instrumentation_default.merge(tasklist_block_diff: 1)

      @result = klass.new(
        tasklist_blocks_previous: [],
        tasklist_blocks_next: [TasklistBlocks::TasklistBlock.new],
        issue: @issue,
        actor: @actor,
      ).call

      assert_hydro_published(expected, schema: "github.v1.TasklistDiff")
      assert_predicate @result, :success?
    end

    test "logs and returns success result when removing tasklist blocks" do
      expected = instrumentation_default.merge(tasklist_block_diff: -1)

      @result = klass.new(
        tasklist_blocks_previous: [TasklistBlocks::TasklistBlock.new],
        tasklist_blocks_next: [],
        issue: @issue,
        actor: @actor,
      ).call

      assert_hydro_published(expected, schema: "github.v1.TasklistDiff")
      assert_predicate @result, :success?
    end

    test "returns success result when no tasklist blocks" do
      result = klass.new(
        tasklist_blocks_previous: [],
        tasklist_blocks_next: [],
        issue: @issue,
        actor: @actor,
      ).call

      assert_predicate result, :success?
    end
  end

  private

  def instrumentation_default
    {
      actor: Hydro::EntitySerializer.user(@actor),
      issue_repository: Hydro::EntitySerializer.repository(@issue.repository),
      issue: Hydro::EntitySerializer.issue(@issue),
      tasklist_block_diff: 0,
      tasklist_item_diff: 0,
    }
  end

  def klass
    TasklistBlockCommands::DiffChanges
  end
end
