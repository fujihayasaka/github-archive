# typed: true
# frozen_string_literal: true

require "test_helper"

class ImportableCommitCommentTest < GitHub::TestCase
  fixtures do
    user = create(:user)
    repo = create(:repository, owner: user)
    @importable_commit_comment = create(:importable_commit_comment, user: user)
  end

  test "has CommitComent type" do
    assert_equal "CommitComment", @importable_commit_comment.type
  end

  test "is both a ImportableCommitComent and CommitComent type" do
    assert @importable_commit_comment.is_a?(ImportableCommitComment)
    assert @importable_commit_comment.is_a?(CommitComment)
  end

  context "#importing?" do
    test "#importing? returns true during import context" do
      assert @importable_commit_comment.importing?
    end

    test "#importing? returns false outside of import context" do
      non_import_commit_comment = CommitComment.find(@importable_commit_comment.id)
      refute non_import_commit_comment.importing?
    end
  end

  context "skipped callbacks" do
    context "#subscribe_and_notify" do
      test "is skipped within an import context" do
        ImportableCommitComment.any_instance.expects(:subscribe_and_notify).never
        create(:importable_commit_comment)
      end

      test "is not skipped outside an import context" do
        CommitComment.any_instance.expects(:subscribe_and_notify).once
        create(:commit_comment)
      end
    end
  end

  context "skipped validations" do
    context "#commit_not_locked" do
      test "is skipped within an import context" do
        Repository.any_instance.stubs(:locked_on_migration?).returns(true)

        ImportableCommitComment.any_instance.expects(:commit_not_locked).never
        create(:importable_commit_comment)
      end

      test "is not skipped outside an import context" do
        Repository.any_instance.stubs(:locked_on_migration?).returns(true)
        expected_error = "Validation failed: Repository has been locked for migration"

        CommitComment.any_instance.expects(:commit_not_locked).once
        assert_raises_with_message ActiveRecord::RecordInvalid, expected_error do
          create(:commit_comment)
        end
      end
    end

    context "#validate_comment_is_authorized" do
      test "is skipped within an import context" do
        ImportableCommitComment.any_instance.expects(:validate_comment_is_authorized).never
        create(:importable_commit_comment)
      end

      test "is not skipped outside an import context" do
        Repository.any_instance.stubs(:locked_on_migration?).returns(true)
        expected_error = "Validation failed: Repository has been locked for migration"

        CommitComment.any_instance.expects(:validate_comment_is_authorized).once
        create(:commit_comment, user: create(:mannequin))
      end
    end
  end
end
