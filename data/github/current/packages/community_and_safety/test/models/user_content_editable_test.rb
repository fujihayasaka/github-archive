# typed: true
# frozen_string_literal: true

require "test_helper"

class UserContentEditableTest < GitHub::TestCase
  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  fixtures do
    @issue = create(:issue, body: "original body", create_references: true)
  end

  test "creates 2 user content edits on first edit" do
    assert_equal 0, @issue.user_content_edits.count
    @issue.update_body("a new body", @issue.user)
    assert_equal 2, @issue.user_content_edits.count
  end

  test "doesn't error when issue has no created_at date" do
    @issue.update(created_at: nil)
    assert_nil @issue.created_at
    @issue.update_body("a new body", @issue.user)
    refute_nil @issue.user_content_edits.first.edited_at
    refute_nil @issue.user_content_edits.last.edited_at
  end

  test "doesn't error when editing non-persisted issues" do
    issue = Issue.new
    issue.update_body("new body", @issue.user)
  end

  test "does not create edit history if issue fails to update" do
    @issue.stubs(:update).returns(false)
    assert_equal 0, @issue.user_content_edits.count
    @issue.update_body("a new body", @issue.user)
    assert_equal 0, @issue.reload.user_content_edits.count
  end

  test "uses given old_diff value for original content edit" do
    old_diff = "some sample value"

    # One to record the original body of the issue, one to record the new body:
    assert_difference(-> { IssueEdit.count }, 2) do
      assert @issue.update_body("a new body", @issue.user, old_diff: old_diff)
    end

    original_edit = @issue.user_content_edits.first
    assert_equal old_diff, original_edit.diff
  end

  test "uses given new_diff value for new content edit when also making an original edit record" do
    new_diff = "some sample value"

    # One to record the original body of the issue, one to record the new body:
    assert_difference(-> { IssueEdit.count }, 2) do
      assert @issue.update_body("a new body", @issue.user, new_diff: new_diff)
    end

    new_edit = @issue.user_content_edits.last
    assert_equal new_diff, new_edit.diff
  end

  test "does not use given old_diff value for original content edit when not making an original edit record" do
    # One to record the original body of the issue, one to record the new body:
    assert_difference(-> { IssueEdit.count }, 2) do
      assert @issue.update_body("a new body", @issue.user)
    end
    assert_equal "original body", @issue.user_content_edits.first.diff
    assert_equal "a new body", @issue.user_content_edits.last.diff

    old_diff = "some sample value"

    # Just the single new edit:
    assert_difference(-> { IssueEdit.count }) do
      assert @issue.update_body("Some Brand New Body", @issue.user, old_diff: old_diff)
    end

    new_edit = @issue.user_content_edits.last
    assert_equal "Some Brand New Body", new_edit.diff
  end

  test "uses given new_diff value for new content edit when not making an original edit record" do
    # One to record the original body of the issue, one to record the new body:
    assert_difference(-> { IssueEdit.count }, 2) do
      assert @issue.update_body("a new body", @issue.user)
    end
    assert_equal "a new body", @issue.user_content_edits.last.diff

    new_diff = "some sample value"

    # Just the single new edit:
    assert_difference(-> { IssueEdit.count }) do
      assert @issue.update_body("Some Brand New Body", @issue.user, new_diff: new_diff)
    end

    new_edit = @issue.user_content_edits.last
    assert_equal new_diff, new_edit.diff
  end

  test "gracefully handles one transient database error" do
    exceptions = [
      { type: ActiveRecord::ConnectionFailed, edit_count: 2, metric_count: 1, new_body: "b1" },
    ]

    GitHub.logger.expects(:info).never

    exceptions.each do |exception|
      @issue.stubs(:update).raises(exception[:type]).then.returns(true)
      @issue.update_body(exception[:new_body], @issue.user)

      assert_equal exception[:edit_count], @issue.user_content_edits.count

      assert_equal exception[:metric_count], GitHub.dogstats.increments("user_content_editable.pass_with_retry", tags: ["object_class:Issue"]).length

      new_edit = @issue.user_content_edits.last
      assert_equal exception[:new_body], new_edit.diff
    end
  end

  test "re-raises transient database error if retries exhausted" do
    @issue.stubs(:update).raises(ActiveRecord::ConnectionFailed)

    new_body = "a new body"

    GitHub.logger.expects(:info).once.with do |_msg, params|
      assert_equal "Issue#update_body", params["code.function"]
      assert_equal @issue.body.length, params["gh.issues.user_content_editable.old_body_length"]
      assert_equal new_body.length, params["gh.issues.user_content_editable.new_body_length"]
      assert_equal @issue.user.id, params["gh.issues.user_content_editable.editor_id"]
      assert_equal @issue.id, params["gh.issues.user_content_editable.object_id"]
      assert_equal Issue.name, params["gh.issues.user_content_editable.object_class"]
    end

    assert_raises(ActiveRecord::ConnectionFailed) { @issue.update_body(new_body, @issue.user) }

    assert_equal 0, @issue.user_content_edits.count

    refute GitHub.dogstats.increments("user_content_editable.pass_with_retry", tags: ["object_class:Issue"]).any?
  end

  context "#add_user_content_edit!" do
    test "creates 2 user content edits on first edit" do
      assert_equal 0, @issue.user_content_edits.count
      @issue.add_user_content_edit!("foo", "bar", @issue.user)
      assert_equal 2, @issue.user_content_edits.count
    end

    test "doesn't error when issue has no created_at date" do
      @issue.update(created_at: nil)
      assert_nil @issue.created_at
      @issue.add_user_content_edit!("a new body", @issue.body, @issue.user)
      refute_nil @issue.user_content_edits.first.edited_at
      refute_nil @issue.user_content_edits.last.edited_at
    end

    test "doesn't error when editing non-persisted issues" do
      issue = Issue.new
      issue.add_user_content_edit!("new body", nil, @issue.user)
      assert_equal 0, @issue.user_content_edits.count
    end

    test "doesn't create edits when content is identical" do
      refute @issue.add_user_content_edit!("identical text", "identical text", @issue.user)
      assert_equal 0, @issue.user_content_edits.count
    end

    test "only creates one content edit on subsequent edits" do
      @issue.add_user_content_edit!("foo", "bar", @issue.user)
      assert_equal 2, @issue.user_content_edits.count

      @issue.add_user_content_edit!("bar", "baz", @issue.user)
      assert_equal 3, @issue.user_content_edits.count
    end
  end

  test "identifies the edit class associated with an arbitrary class name" do
    assert_equal "UserContentEdit", UserContentEditable.edit_class_for("OrganizationDiscussionItem")
    assert_equal "DiscussionEdit", UserContentEditable.edit_class_for("Discussion")
    assert_equal "RepositoryAdvisoryCommentEdit", UserContentEditable.edit_class_for("RepositoryAdvisoryComment")
  end

  test "identifies known custom edit classes" do
    assert UserContentEditable.is_custom_edit_class?("IssueCommentEdit"),
      "expected IssueCommentEdit to be a valid custom edit class"
    refute UserContentEditable.is_custom_edit_class?("WhyWouldYouNameAClassThis"),
      "expected to recognize something that isn't a valid custom edit class"
  end

  context "#async_latest_user_content_edit" do
    test "doesn't make more queries when called additional times" do
      assert_query_count 1, ignore_feature_flags: true do
        @issue.async_latest_user_content_edit.sync
      end

      assert_query_count 0, ignore_feature_flags: true do
        @issue.async_latest_user_content_edit.sync
      end
    end

    test "returns the same record when called additional times" do
      @issue.add_user_content_edit!("foo", "bar", @issue.user)

      first_result = @issue.async_latest_user_content_edit.sync
      second_result = @issue.async_latest_user_content_edit.sync

      assert_equal first_result, second_result
    end
  end

  context "#async_edited_by_another_user?" do
    test "returns false if latest_user_content_edit is already loaded and nil" do
      # load association
      @issue.latest_user_content_edit

      assert_equal false, @issue.async_edited_by_another_user?.sync
    end

    test "returns false if no other user has edited this issue, even if latest_user_content_edit is already loaded and not nil" do
      @issue.add_user_content_edit!("foo", "bar", @issue.user)
      # load association
      @issue.latest_user_content_edit

      assert_equal false, @issue.async_edited_by_another_user?.sync
    end

    test "returns true if another user has edited this issue, even if latest_user_content_edit is already loaded and not nil" do
      # other user's edit
      @issue.add_user_content_edit!("foo", "bar", create(:user))

      @issue.add_user_content_edit!("foo", "bar", @issue.user)
      # load association
      @issue.latest_user_content_edit

      assert_equal true, @issue.async_edited_by_another_user?.sync
    end

    test "doesn't make a query if latest_user_content_edit is already loaded" do
      # load association
      @issue.latest_user_content_edit

      assert_max_query_count 0, ignore_feature_flags: true do
        @issue.async_edited_by_another_user?.sync
      end
    end

    test "executes queries if latest_user_content_edit isn't already loaded" do
      assert_query_count 2, ignore_feature_flags: true do
        @issue.async_edited_by_another_user?.sync
      end
    end

    test "deletes dependents for issue and issue comment" do
      issue = create(:issue, create_references: true, body: "original body")
      issue_comment = create(:issue_comment, body: "original comment body", issue: issue)

      issue.update_body("a new body", @issue.user)
      issue_comment.update_body("a new comment body", @issue.user)

      comment_arg_matcher = ->(args) do
        args[0] == "IssueComment" &&
          args[1] == issue_comment.id &&
          args[2] == :user_content_edits &&
          args[3][:sharding_key] == :repository_id &&
          args[3][:sharding_value] == issue_comment.repository_id &&
          args[3][:cross_shard_query_exempted] == false
      end

      assert_enqueued_with(job: DestroyDependentRecordsJob, args: comment_arg_matcher) do
        perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { issue_comment.destroy }
      end

      issue_arg_matcher = ->(args) do
        args[0] == "Issue" &&
          args[1] == issue.id &&
          args[2] == :user_content_edits &&
          args[3][:sharding_key] == :repository_id &&
          args[3][:sharding_value] == issue.repository_id &&
          args[3][:cross_shard_query_exempted] == false

      end

      assert_enqueued_with(job: DestroyDependentRecordsJob, args: issue_arg_matcher) do
        perform_enqueued_jobs(only: [ProcessMentionedReferencesJob]) { issue.destroy }
      end
    end
  end
end
