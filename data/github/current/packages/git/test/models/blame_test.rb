# typed: true
# frozen_string_literal: true

require "test_helper"

class BlameTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd

    example_repo :mojombo_grit, @repo
    @commit = @repo.commit_for_ref("master")
    @blame = Blame.new(@repo, @commit.oid, "History.txt")
  end

  test "iterating over blame lines" do
    lines = ["== 1.0.0 / 2007-10-09", "", "* 1 major enhancement", "  * Birthday!", ""]
    count = 0
    @blame.each do |lineno, _old_lineno, commit, text, _|
      count += 1
      assert_equal count, lineno
      assert commit.is_a?(Commit)
      assert_equal "634396b2f541a9f2d58b00be1a07f0c358b999b3", commit.oid
      assert_equal lines.shift, text
    end
    assert_equal 5, count
  end

  test "can reblame changed line" do
    blame = Blame.new(@repo, @commit.oid, "lib/grit.rb")
    line_number, old_line_number, commit, text, reblame_path = blame.first

    assert_equal "lib/grit.rb", reblame_path
    assert_equal "337539e896b8c85cc043a923c8fbb927f58e6450", commit.oid
    assert_equal "$:.unshift File.dirname(__FILE__) # For use/testing when no gem is installed", text
    assert_equal 1, line_number
    assert_equal 1, old_line_number
  end

  test "can reblame all lines changed by a given commit" do
    # In the mojombo_grit repo, two lines in `lib/grit.rb` were changed in
    # commit 337539e: line 1 and line 26.

    blame = Blame.new(@repo, @commit.oid, "lib/grit.rb")

    # line 1
    line_number, old_line_number, commit, text, reblame_path = blame.to_a[0]
    assert_equal "lib/grit.rb", reblame_path
    assert_equal "337539e896b8c85cc043a923c8fbb927f58e6450", commit.oid

    # line 26
    line_number, old_line_number, commit, text, reblame_path = blame.to_a[25]
    assert_equal "lib/grit.rb", reblame_path
    assert_equal "337539e896b8c85cc043a923c8fbb927f58e6450", commit.oid
  end

  test "can reblame line that was changed in a commit that renamed the file" do
    # In the mojombo_grit repo, `test/test_repo.rb` was originally named
    # `test/test_grit.rb`. Commit d01a4cf changed line 3 *and* renamed the file.
    # To reblame line 5 at the parent of d01a4cf, we need to use the file's
    # *previous* path.

    blame = Blame.new(@repo, @commit.oid, "test/test_repo.rb")
    line_number, old_line_number, commit, text, reblame_path = blame.to_a[2]

    assert_equal "test/test_grit.rb", reblame_path
    assert_equal "d01a4cfad6ea50285c4710243e3cbe019d381eba", commit.oid
    assert_match /\Aclass TestRepo/, text
    assert_equal 3, line_number
    assert_equal 3, old_line_number
  end

  test "cannot reblame line that was added in the commit that added the file" do
    blame = Blame.new(@repo, @commit.oid, ".gitignore")
    line_number, old_line_number, commit, text, reblame_path = blame.first

    assert_nil reblame_path
    assert_equal "34a87f9a723cc51b6b74e0fe095c9046a826ef3b", commit.oid
    assert_equal "coverage", text
    assert_equal 1, line_number
    assert_equal 1, old_line_number
  end

  test "blame file has lines in it" do
    refute @blame.empty?
  end

  test "indexes commits on OID" do
    assert_equal ["634396b2f541a9f2d58b00be1a07f0c358b999b3"], @blame.commits.keys
    assert_kind_of Commit, @blame.commits.values.first
  end

  test "dedupes commits before calling read_objects" do
    @repo.rpc.expects(:read_objects)
      .with(["634396b2f541a9f2d58b00be1a07f0c358b999b3"], "commit", false)
      .returns([])

    @blame.commits
  end

  test "returns no line data when path is invalid" do
    blame = Blame.new(@repo, @commit.oid, "lib/imaginary-file.rb")
    assert_empty blame.line_data
    assert blame.empty?
  end

  test "returns no line data when requested lines are invalid" do
    blame = Blame.new(@repo, @commit.oid, "test/test_repo.rb", line_numbers: [100_000])
    assert_empty blame.line_data
    assert blame.empty?
  end

  test "filters commits by 'since' date" do
    @commit = Spokesd.with_spokesd_disabled do
      @repo.heads.find("master").append_commit(
      { message: "new file", committer: @repo.owner, committed_date: 1.year.ago.iso8601 }, @repo.owner
    ) { |files| files.add("changes.txt", "changes") }
    end

    unscoped_lines = Blame.new(@repo, @commit, "changes.txt").lines
    assert_equal unscoped_lines[0][2], @commit

    scoped_including_lines = Blame.new(@repo, @commit, "changes.txt", since: (1.year.ago - 1.day)).lines
    assert_equal scoped_including_lines[0][2], @commit

    scoped_excluding_lines = Blame.new(@repo, @commit, "changes.txt", since: 1.minute.ago).lines
    assert scoped_excluding_lines.empty?
  end

  context "ignore-revs-file" do
    test "#has_ignore_revs_file? returns true when file exists" do
      blame = Blame.new(@repo, @repo.commit_for_ref("master"), "changes.txt")
      refute blame.has_ignore_revs_file?

      commit_with_file = Spokesd.with_spokesd_disabled do
        @repo.heads.find("master").append_commit(
        { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
      ) { |files| files.add(Blame::IGNORE_REVS_FILE_PATH, "# Empty file") }
      end

      blame = Blame.new(@repo, commit_with_file, "changes.txt")
      assert blame.has_ignore_revs_file?
    end

    test "filters commits in the `.git-blame-ignore-revs` file" do
      head = @repo.heads.find("master")

      oid = Spokesd.with_spokesd_disabled do
        first_commit = head.append_commit(
          { message: "new file", committer: @repo.owner, committed_date: 1.year.ago.iso8601 }, @repo.owner
        ) { |files| files.add("changes.txt", "changes") }

        commit_to_ignore = head.append_commit(
          { message: "new file", committer: @repo.owner, committed_date: 1.year.ago.iso8601 }, @repo.owner
        ) { |files| files.remove("changes.txt"); files.add("changes.txt", "changes;") }

        blame = Blame.new(@repo, @repo.commit_for_ref("master"), "changes.txt")
        assert_equal blame.lines.first[2], commit_to_ignore

        head.append_commit(
          { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
        ) { |files| files.add(Blame::IGNORE_REVS_FILE_PATH, "# Ignore this:\n#{commit_to_ignore}") }

        first_commit
      end

      blame = Blame.new(@repo, @repo.commit_for_ref("master"), "changes.txt")
      assert_equal blame.lines.first[2], oid
    end

    test "works as normal if the file does not exist" do
      blame = Blame.new(@repo, @commit.oid, "History.txt")
      refute blame.lines.empty?
    end

    test "raises GitRPC::InvalidIgnoreRevs for invalid ignore revs file" do
      @commit = Spokesd.with_spokesd_disabled do
        @repo.heads.find("master").append_commit(
        { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
      ) { |files| files.add(Blame::IGNORE_REVS_FILE_PATH, "not valid") }
      end

      blame = Blame.new(@repo, @commit.oid, "History.txt")
      assert_raises GitRPC::InvalidIgnoreRevs do
        blame.lines
      end
    end

    test "blame_cache_key includes oid of `.git-blame-ignore-revs` file with flag" do
      added_ignore_file = Spokesd.with_spokesd_disabled do
        @repo.heads.find("master").append_commit(
        { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
      ) { |files| files.add(Blame::IGNORE_REVS_FILE_PATH, "# Empty file") }
      end
      tree_entry_oid = @repo.read_tree_entry_oid(added_ignore_file.oid, Blame::IGNORE_REVS_FILE_PATH)

      blame = Blame.new(@repo, added_ignore_file.oid, "History.txt")
      assert_match /:#{tree_entry_oid}\z/, blame.blame_cache_key
    end

    test "raises GitRPC::IgnoreRevsTooBig for a large (but valid) file" do
      @commit = Spokesd.with_spokesd_disabled do
        @repo.heads.find("master").append_commit(
          { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
        ) { |files| files.add(Blame::IGNORE_REVS_FILE_PATH, "# " + "a" * 1.megabyte) }
      end

      blame = Blame.new(@repo, @commit.oid, "History.txt")
      assert_raises GitRPC::IgnoreRevsTooBig do
        blame.lines
      end
    end

    test "raises GitRPC::SymlinkDisallowed for symlinks" do
      latest_commit = Spokesd.with_spokesd_disabled do
        @repo.heads.find("master").append_commit(
        { message: "Add ignore revs file", committer: @repo.owner }, @repo.owner
      ) do |files|
        files.add(Blame::IGNORE_REVS_FILE_PATH, "different-file.txt", mode: 0120000)
        files.add("different-file.txt", "# Ignore this")
      end
      end

      blame = Blame.new(@repo, latest_commit, "History.txt")
      assert_raises GitRPC::SymlinkDisallowed do
        blame.lines
      end
    end
  end
end
