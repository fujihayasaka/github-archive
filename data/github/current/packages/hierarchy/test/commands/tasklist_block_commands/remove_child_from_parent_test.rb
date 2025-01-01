# typed: true
# frozen_string_literal: true

require "test_helper"

class TasklistBlockCommands::RemoveChildFromParentTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @repo = create(:repository)
    @child_issue = create(:issue, repository: @repo)
    @other_repo = create(:repository)
    @child_issue_other_repo = create(:issue, repository: @other_repo)
    @actor = create(:user)
  end

  setup do
    tasklist_body = <<~MD
    ```[tasklist]
    ### title
    - [ ] #1
    ```
    MD
    # normally this would be in fixtures but because we want to stub this
    # method, we instead move it to a setup block.
  end

  sig { params(body: String).void }
  def build_parent_with_body(body)
    @parent_issue = build(:issue, body: body, repository: @repo)
    @parent_issue.stubs(:reconcile_tracking_blocks_after_save).returns(true)
    @parent_issue.save!
  end

  context "happy path" do
    test "it updates the body when there is a number reference" do
      build_parent_with_body(
        <<~MD
        ```[tasklist]
        ### title
        - [ ] ##{@child_issue.number}
        - [ ] #5
        ```
        MD
      )
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
      ).call

      expected = <<~MD
        ```[tasklist]
        ### title
        - [ ] #5
        ```
      MD
      assert_equal expected, @parent_issue.reload.body
      assert_predicate result, :success?
      assert_dogstats_increment 1,
        TasklistBlockCommands::RemoveChildFromParent::METRIC_NAME,
        tags: ["status:success"]
    end

    test "it updates the body when there is a url reference" do
      build_parent_with_body(
        <<~MD
        ```[tasklist]
        ### title
        - [ ] #{@child_issue.url}
        - [ ] #5
        ```
        MD
      )
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
      ).call

      expected = <<~MD
        ```[tasklist]
        ### title
        - [ ] #5
        ```
      MD
      assert_equal expected, @parent_issue.reload.body
      assert_predicate result, :success?
      assert_dogstats_increment 1,
        TasklistBlockCommands::RemoveChildFromParent::METRIC_NAME,
        tags: ["status:success"]
    end

    test "it updates the body when there is an nwo reference" do
      build_parent_with_body(
        <<~MD
        ```[tasklist]
        ### title
        - [ ] #{@child_issue.url}
        - [ ] #{@child_issue_other_repo.repository.name_with_display_owner}##{@child_issue_other_repo.number}
        ```
        MD
      )
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue_other_repo,
        actor: @actor,
      ).call

      expected = <<~MD
        ```[tasklist]
        ### title
        - [ ] #{@child_issue.url}
        ```
      MD
      assert_equal expected, @parent_issue.reload.body
      assert_predicate result, :success?
      assert_dogstats_increment 1,
        TasklistBlockCommands::RemoveChildFromParent::METRIC_NAME,
        tags: ["status:success"]
    end
    test "it updates the body when there are two references to child issue" do
      build_parent_with_body(
        <<~MD
        ```[tasklist]
        ### title
        - [ ] #{@child_issue.url}
        - [ ] #{@child_issue_other_repo.repository.name_with_display_owner}##{@child_issue_other_repo.number}
        ```

        ```[tasklist]
        ### title2
        - [ ] some other task
        - [ ] #{@child_issue_other_repo.repository.name_with_display_owner}##{@child_issue_other_repo.number}
        ```
        MD
      )
      result = klass.new(
        parent: @parent_issue,
        child: @child_issue_other_repo,
        actor: @actor,
      ).call

      expected = <<~MD
        ```[tasklist]
        ### title
        - [ ] #{@child_issue.url}
        ```

        ```[tasklist]
        ### title2
        - [ ] some other task
        ```
      MD
      assert_equal expected, @parent_issue.reload.body
      assert_predicate result, :success?
      assert_dogstats_increment 1,
        TasklistBlockCommands::RemoveChildFromParent::METRIC_NAME,
        tags: ["status:success"]
    end
  end

  context "when item is not in issue" do
    test "it does not update the issue body" do
      build_parent_with_body(
        <<~MD
        ```[tasklist]
        ### title
        - [ ] some other task
        ```
        MD
      )

      result = klass.new(
        parent: @parent_issue,
        child: @child_issue,
        actor: @actor,
      ).call

      refute @parent_issue.reload.body.include?(@child_issue.url)
      refute_predicate result, :success?

      assert_dogstats_increment 1,
        TasklistBlockCommands::RemoveChildFromParent::METRIC_NAME,
        tags: ["status:failure"]
    end
  end

  private

  def klass
    TasklistBlockCommands::RemoveChildFromParent
  end
end
