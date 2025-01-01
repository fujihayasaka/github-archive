# typed: true
# frozen_string_literal: true

require "test_helper"

class DeletedDiscussionTest < GitHub::TestCase
  context "validations" do
    test "requires a deleting user" do
      deleted_discussion = DeletedDiscussion.new
      refute_predicate deleted_discussion, :valid?
      assert_includes deleted_discussion.errors[:deleted_by], "must exist"
    end

    test "requires a repository" do
      deleted_discussion = DeletedDiscussion.new
      refute_predicate deleted_discussion, :valid?
      assert_includes deleted_discussion.errors[:repository], "must exist"
    end

    test "requires an old discussion ID" do
      deleted_discussion = DeletedDiscussion.new
      refute_predicate deleted_discussion, :valid?
      assert_includes deleted_discussion.errors[:old_discussion_id], "can't be blank"
    end

    test "requires a number" do
      deleted_discussion = DeletedDiscussion.new
      refute_predicate deleted_discussion, :valid?
      assert_includes deleted_discussion.errors[:number], "can't be blank"
    end

    test "requires a unique number per repository" do
      deleted_discussion = create(:deleted_discussion)
      dupe = DeletedDiscussion.new(number: deleted_discussion.number,
        repository_id: deleted_discussion.repository_id)
      refute_predicate dupe, :valid?
      assert_includes dupe.errors[:number], "has already been taken"
    end
  end
end
