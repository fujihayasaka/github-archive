# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueEditTest < GitHub::TestCase
  fixtures do
    @issue = create(:issue, body: "old body")
    @issue.update_body("new body", @issue.user)

    @issue_edit = IssueEdit.where(issue: @issue).last

    @legacy_issue = create(:issue, body: "old body")
    @legacy_issue.update_body("new body", @legacy_issue.user)

    @legacy_issue_edit = IssueEdit.where(issue: @legacy_issue).last
    T.must(@legacy_issue_edit).update(user_content_edit_id: 1)
  end

  context "#global_relay_id" do
    test "for a non-legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@issue_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@issue_edit)
        assert_equal id, ["UserContentEdit", @issue_edit.id]
      else
        assert_equal id, ["UserContentEdit", "IssueEdit:#{@issue_edit.id}"]
      end
    end

    test "for a legacy edit" do
      id = Platform::Helpers::NodeIdentification.from_global_id(@legacy_issue_edit.global_relay_id)
      if Platform::Objects::UserContentEdit.use_next_id?(@legacy_issue_edit)
        assert_equal id, ["UserContentEdit", @legacy_issue_edit.id]
      else
        assert_equal id, ["UserContentEdit", "#{@legacy_issue_edit.user_content_edit_id}"]
      end
    end
  end

  test "#soft_delete!" do
    user = create(:user)
    events = subscribe "user_content_edit.delete"

    Timecop.freeze do
      expected_payload = {
        user_content_type: "Issue",
        user_content_id: @issue.id,
        editor: @issue_edit.editor.login,
        editor_id: @issue_edit.editor.id,
        deleted_by: user.login,
        deleted_by_id: user.id,
        deleted_content: "new body",
      }

      @issue_edit.soft_delete!(user)

      assert event = events.pop, "an event was expected"
      assert_same_time Time.zone.now, event.payload.delete(:deleted_at)
      assert_equal expected_payload, event.payload
      assert_equal @issue_edit.deleted_by, user
      refute_nil @issue_edit.deleted_at
    end
  end

  test "#diff_before" do
    assert_equal "new body", @issue_edit.diff
    assert_equal "old body", @issue_edit.diff_before

    @issue.update_body("newer body", @issue.user)
    assert_equal "new body", T.must(IssueEdit.where(issue: @issue).last).diff_before
  end

  test "isn't created when no changes are made" do
    old_body = @issue.body

    assert_no_difference(-> { IssueEdit.count }, -> { UserContentEdit.count }) do
      @issue.update_body(old_body, @issue.user)
    end
  end

  context "#safe_diff" do
    test "returns the valid body" do
      assert_equal @issue_edit.diff, @issue_edit.safe_diff
    end

    test "encodes emoji correctly" do
      string = "😉".b
      @issue_edit.update_attribute(:diff, string)
      assert_equal Encoding::UTF_8, @issue_edit.diff.encoding
      assert_equal Encoding::UTF_8, @issue_edit.safe_diff.encoding
    end
  end

  test "sets `repository_id` from the issue" do
    refute_nil @issue_edit.repository_id
    assert_equal @issue_edit.repository_id, @issue.repository_id
  end

  context "compressed diff" do
    test "assigning a diff writes to the compressed_diff column" do
      new_diff = "this is the new diff"
      @issue_edit.diff = new_diff

      assert_equal new_diff, @issue_edit.compressed_diff

      assert @issue_edit.save

      @issue_edit.reload

      assert_equal new_diff, @issue_edit.diff
      assert_equal new_diff, @issue_edit.compressed_diff
    end

    test "is actually compressing the compressed_diff" do
      diff = @issue_edit.diff

      compressed_diff_raw = @issue_edit.attributes_before_type_cast["compressed_diff"]

      compressed_binary_representation = CompressedBinary.new("IssueEdit", "diff")
      assert_equal diff, compressed_binary_representation.deserialize(compressed_diff_raw)
      assert_equal compressed_binary_representation.serialize(diff), compressed_diff_raw
    end
  end
end
