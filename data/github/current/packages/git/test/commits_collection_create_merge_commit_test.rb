# typed: true
# frozen_string_literal: true

require "test_helper"

class CommitsCollectionCreateMergeCommitTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  setup do
    example_repo :merge_ort, @repo
    reset_cache
    @collection = CommitsCollection.new(@repo)
  end

  def create_merge_commit(base_ref_name, head_ref_name, **kwargs)
    @collection.create_merge_commit(@repo.owner, base_ref_name, head_ref_name, **kwargs)
  end

  def oid(name)
    @repo.refs.find(name).target.oid
  end

  test "regular merge: PR branch with commits ahead of base branch" do
    value = create_merge_commit(
      "main-regular-merge-1",
      "pr-regular-merge-1",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-regular-merge-1"),
      oid("pr-regular-merge-1"),
    ], merge_commit.parent_oids
  end

  test "regular merge: PR branch and base branch diverge but without conflicts" do
    value = create_merge_commit(
      "main-regular-merge-2",
      "pr-regular-merge-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-regular-merge-2"),
      oid("pr-regular-merge-2"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-regular-merge-2",
      "main-regular-merge-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("pr-regular-merge-2"),
      oid("main-regular-merge-2"),
    ], merge_commit.parent_oids
  end

  test "regular merge: passing options" do
    commit_message = "custom commit message"
    commit_time = Time.find_zone("UTC").local(2022, 1, 1)
    value = create_merge_commit(
      "main-regular-merge-2",
      "pr-regular-merge-2",
      commit_message:,
      commit_time:
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-regular-merge-2"),
      oid("pr-regular-merge-2"),
    ], merge_commit.parent_oids

    assert_equal commit_message, merge_commit.message
    assert_equal commit_time, merge_commit.committed_date
  end

  test "applied merge: PR branch is already merged" do
    value = create_merge_commit(
      "main-applied-merge-1-post",
      "pr-applied-merge-1",
    )

    assert_equal [nil, :already_merged], value

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-applied-merge-1",
      "main-applied-merge-1-post",
    )

    # Note in this direction it ends up being an actual merge.
    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("pr-applied-merge-1"),
      oid("main-applied-merge-1-post"),
    ], merge_commit.parent_oids
  end

  test "conflict: PR branch and base branch touch the same part of a file" do
    value = create_merge_commit(
      "main-conflict-1",
      "pr-conflict-1",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-1",
      "main-conflict-1",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: passing in resolutions" do
    contents = "New contents with conflicts resolved"
    value = create_merge_commit(
      "main-conflict-1",
      "pr-conflict-1",
      resolve_conflicts: {
        "README.md" => contents,
      }
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-conflict-1"),
      oid("pr-conflict-1"),
    ], merge_commit.parent_oids

    assert_equal contents, merge_commit.repository.tree_entry(merge_commit.tree_oid, "README.md").data
  end

  test "conflict: PR branch converts file to symlink, base branch modifies file" do
    value = create_merge_commit(
      "main-conflict-2",
      "pr-conflict-2",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-2",
      "main-conflict-2",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: PR branch modifies file, base branch replaces with directory" do
    value = create_merge_commit(
      "main-conflict-3",
      "pr-conflict-3",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-3",
      "main-conflict-3",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: PR branch modifies file, base branch replaces with directory (no rename)" do
    # merge-ort would detect a rename in the previous example if we didn't pass
    # the merge.renames=false configuration flag; this example uses as input
    # something that wouldn't trigger rename detection.
    value = create_merge_commit(
      "main-conflict-3b",
      "pr-conflict-3b",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-3b",
      "main-conflict-3b",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: PR branch turns file into symlink, base branch modifies contents" do
    value = create_merge_commit(
      "main-conflict-4",
      "pr-conflict-4",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-4",
      "main-conflict-4",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "(hypothetical) conflict: PR branch renames file one way, base branch renames it a different way" do
    value = create_merge_commit(
      "main-conflict-5",
      "pr-conflict-5",
    )

    # Note that this _should_ be a merge conflict but is not in libgit2 because
    # we have no rename detection (and have therefore turned it off in merge-ort
    # too, at least for now).
    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-conflict-5"),
      oid("pr-conflict-5"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-5",
      "main-conflict-5",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("pr-conflict-5"),
      oid("main-conflict-5"),
    ], merge_commit.parent_oids
  end

  test "conflict: PR branch deletes a file, base branch modifies contents" do
    value = create_merge_commit(
      "main-conflict-6",
      "pr-conflict-6",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-6",
      "main-conflict-6",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: PR branch modifies a file, base branch deletes it" do
    value = create_merge_commit(
      "main-conflict-7",
      "pr-conflict-7",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-7",
      "main-conflict-7",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict involving a non-UTF-8 encoded filename" do
    value = create_merge_commit(
      "main-conflict-9",
      "pr-conflict-9",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-9",
      "main-conflict-9",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "criss-cross merge" do
    value = create_merge_commit(
      "criss-cross-merge-left",
      "criss-cross-merge-right",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("criss-cross-merge-left"),
      oid("criss-cross-merge-right"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "criss-cross-merge-right",
      "criss-cross-merge-left",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("criss-cross-merge-right"),
      oid("criss-cross-merge-left"),
    ], merge_commit.parent_oids
  end

  test "unrelated histories that merge cleanly (touching different files)" do
    value = create_merge_commit(
      "main-before-merging-orphan-1",
      "orphan-1",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-before-merging-orphan-1"),
      oid("orphan-1"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "orphan-1",
      "main-before-merging-orphan-1",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("orphan-1"),
      oid("main-before-merging-orphan-1"),
    ], merge_commit.parent_oids
  end

  test "unrelated histories that merge cleanly (modifying same file without conflicts)" do
    # In order for there to be no conflicts, one branch must create the file but
    # not add any contents to it.
    value = create_merge_commit(
      "main-before-merging-orphan-2",
      "orphan-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-before-merging-orphan-2"),
      oid("orphan-2"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "orphan-2",
      "main-before-merging-orphan-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("orphan-2"),
      oid("main-before-merging-orphan-2"),
    ], merge_commit.parent_oids
  end

  test "conflict: unrelated histories modifying the same file" do
    value = create_merge_commit(
      "main-conflict-8",
      "orphan-conflict-8",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "orphan-conflict-8",
      "main-conflict-8",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "merging two empty trees" do
    value = create_merge_commit(
      "empty-base-1",
      "empty-pr-1",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("empty-base-1"),
      oid("empty-pr-1"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "empty-pr-1",
      "empty-base-1",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("empty-pr-1"),
      oid("empty-base-1"),
    ], merge_commit.parent_oids
  end

  test "merging a non-empty tree into an empty tree" do
    value = create_merge_commit(
      "empty-base-2",
      "non-empty-pr-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("empty-base-2"),
      oid("non-empty-pr-2"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "non-empty-pr-2",
      "empty-base-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("non-empty-pr-2"),
      oid("empty-base-2"),
    ], merge_commit.parent_oids
  end

  test "merging an empty tree into a non-empty tree" do
    value = create_merge_commit(
      "empty-base-2",
      "non-empty-pr-2",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("empty-base-2"),
      oid("non-empty-pr-2"),
    ], merge_commit.parent_oids

    # Same, with swapped branches.
    value = create_merge_commit(
      "empty-pr-3",
      "non-empty-base-3",
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("empty-pr-3"),
      oid("non-empty-base-3"),
    ], merge_commit.parent_oids
  end

  test "conflict: kitchen sink example with several different kinds of conflict" do
    # left branch:              right branch:
    #
    # adds a file (alpha)       adds a different file (bravo, no conflict)
    # adds a file (charlie)     adds same file but with different contents (charlie)
    # removes a file (delta)    removes same file (delta, no conflict)
    # modifies a file (echo)    modifies a different file (foxtrot)
    # modifies a file (golf)    modifies same file without conflict (golf, no contlict)
    # modifies a file (hotel)   modifies same file with conflict (hotel)
    # modifies a file (india)   turns file into a directory (india/contents)
    # modifies a file (juliett) turns file into a symlink (juliett)
    # modifies a file (kilo)    deletes same file (kilo)
    # adds a file (lima)        adds a directory at the same location (lima/contents)
    # adds a symlink (mike)     adds a conflicting symlink at same location (mike)
    #
    # ie. not an exhaustive list of all possible conflicts but an "interesting
    # assortment".
    #
    value = create_merge_commit(
      "main-conflict-10",
      "pr-conflict-10",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error

    # Same, with swapped branches.
    value = create_merge_commit(
      "pr-conflict-10",
      "main-conflict-10",
    )

    merge_commit, error = value
    assert_nil merge_commit
    assert_equal :merge_conflict, error
  end

  test "conflict: mode is preserved when passing in resolutions" do
    # Regression test for: https://github.com/github/pull-requests/issues/6233
    contents = {
      "LICENSE.txt" => "This project is in the public domain",
      "script.sh" => "#!/bin/sh\n\necho hi\n",
    }
    value = create_merge_commit(
      "main-conflict-11",
      "pr-conflict-11",
      resolve_conflicts: contents,
    )

    merge_commit, error = value
    assert_nil error
    assert_equal [
      oid("main-conflict-11"),
      oid("pr-conflict-11"),
    ], merge_commit.parent_oids

    assert_equal contents["LICENSE.txt"], merge_commit.repository.tree_entry(merge_commit.tree_oid, "LICENSE.txt").data
    assert_equal contents["script.sh"], merge_commit.repository.tree_entry(merge_commit.tree_oid, "script.sh").data

    assert_equal "100644", merge_commit.repository.tree_entry(merge_commit.tree_oid, "LICENSE.txt").mode
    assert_equal "100755", merge_commit.repository.tree_entry(merge_commit.tree_oid, "script.sh").mode
  end
end
