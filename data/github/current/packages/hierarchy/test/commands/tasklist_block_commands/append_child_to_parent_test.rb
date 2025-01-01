# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::AppendChildToParentTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @child_issue = create(:issue)
    @actor = create(:user)
  end

  setup do
    tasklist_body = <<~MD
    ```[tasklist]
    ### title
    - [ ] item 1
    ```
    MD
    # normally this would be in fixtures but because we want to stub this
    # method, we instead move it to a setup block.
    @parent_issue = build(:issue, body: tasklist_body)
    @parent_issue.stubs(:reconcile_tracking_blocks_after_save).returns(true)
    @parent_issue.save!
  end

  context "happy path" do
    test "it updates the issue body" do
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
      ).call

      assert @parent_issue.reload.body.include?(@child_issue.url)
      assert_predicate result, :success?
    end

    test "increments a success metric" do
      klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
      ).call

      assert_dogstats_increment 1,
        TasklistBlockCommands::AppendChildToParent::METRIC_NAME,
        tags: ["status:success"]
    end
  end

  context "when position is out of bounds of parent tasklist indices" do
    test "it does not update the issue body" do
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
        position: 1_000,
      ).call

      refute @parent_issue.reload.body.include?(@child_issue.url)
      refute_predicate result, :success?
    end

    test "increments a failure metric" do
      klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
        position: 1_000,
      ).call

      assert_dogstats_increment 1,
        TasklistBlockCommands::AppendChildToParent::METRIC_NAME,
        tags: ["status:failure"]
    end
  end

  private

  def klass
    TasklistBlockCommands::AppendChildToParent
  end
end
