# typed: strict
# frozen_string_literal: true

require "test_helper"

class CommitDiffStatsTest < GitHub::TestCase
  context "file statistics" do
    test "computes the number of files added, deleted, and modified" do
      repo = create(:repository, from_example: :simple)
      commit = create(:commit, repository: repo, changes: -> (files) {
        files.add("foo.txt", "FOO")
        files.add("bar.txt", "FOO")
        files.add("empty_file", "with stuff in it!")
        files.remove("a")
      })

      stats = Commit::DiffStats.new(commit.diff)

      assert_equal 2, stats.files_added
      assert_equal 1, stats.files_deleted
      assert_equal 4, stats.files_modified
    end
  end

  context "line statistics" do
    test "computes the number of lines added and deleted" do
      repo = create(:repository, from_example: :simple)
      commit = create(:commit, repository: repo, changes: -> (files) {
        files.add("README.md", "# My Project\n")
        files.add("main.rb", "puts 'Hello, world!'\nexit 0\n")
      })

      stats = Commit::DiffStats.new(commit.diff)

      assert_equal 3, stats.lines_added
      assert_equal 0, stats.lines_deleted
      assert_equal({ "Ruby" => 2, "Markdown" => 1 }, stats.lines_added_by_language)
      assert_equal({}, stats.lines_deleted_by_language)

      new_commit = create(:commit, repository: repo, changes: -> (files) {
        files.remove("README.md")
        files.remove("main.rb")
      })

      new_stats = Commit::DiffStats.new(new_commit.diff)

      assert_equal 0, new_stats.lines_added
      assert_equal 3, new_stats.lines_deleted
      assert_equal({}, new_stats.lines_added_by_language)
      assert_equal({ "Ruby" => 2, "Markdown" => 1 }, new_stats.lines_deleted_by_language)
    end
  end

  test "handles commits with no diff text" do
    repo = create(:repository, from_example: :simple)
    create(:commit, repository: repo, changes: -> (files) {
      files.add("README.txt", "# My Project\n")
    })
    commit = create(:commit, repository: repo, changes: -> (files) {
      files.move("README.txt", "README.md", "# My Project\n")
    })

    assert commit.diff.map(&:text).all?(&:nil?),
      "Invalid setup: Test was written assuming Diff::Entry#text would be `nil`"

    stats = Commit::DiffStats.new(commit.diff)

    assert_equal 0, stats.files_added
    assert_equal 0, stats.files_deleted
    assert_equal 1, stats.files_modified
    assert_equal 0, stats.lines_added
    assert_equal 0, stats.lines_deleted
    assert_predicate stats.lines_added_by_language, :empty?
    assert_predicate stats.lines_deleted_by_language, :empty?
  end
end
