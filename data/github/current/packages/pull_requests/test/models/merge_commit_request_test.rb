# typed: true
# frozen_string_literal: true

require "test_helper"

class MergeCommitRequestTest < GitHub::TestCase
  test "it can deserialize valid database enum values" do
    model = MergeCommitRequest.new(merge_state: "created", rebase_state: "skipped")
    assert_equal PullRequests::MergeCommit::Enums::CommitState::Created, model.merge_state_value
    assert_equal PullRequests::MergeCommit::Enums::CommitState::Skipped, model.rebase_state_value
    refute model.pending_deletion?
  end

  test "it can deserialize invalid database values" do
    model = MergeCommitRequest.new(merge_state: "hello", rebase_state: "world")
    assert_nil model.merge_state_value
    assert_nil model.rebase_state_value
  end

  test "is a deletion if the merge state is delete" do
    model = MergeCommitRequest.new(merge_state: "delete", rebase_state: "delete")
    assert model.pending_deletion?
  end
end
