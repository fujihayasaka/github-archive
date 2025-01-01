# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/spokesd"

class TreeHistoryTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    Spokesd.enable_spokesd

    @repo = create(:repository)
    @owner = @repo.owner
    @collab = create(:user)
    @repo.add_member(@collab)
    @collab.watch_repo(@repo)
    @repo_with_over_limit_directory = create(:repository)
  end

  setup do
    Spokesd.enable_spokesd
    reset_cache
    enable_cache_storage
    example_repo :mojombo_grit, @repo
    example_repo :directory_over_entry_limit, @repo_with_over_limit_directory
    @tree_history = @repo.directory(@repo.ref_to_sha("master"), path = "").tree_history
  end

  teardown do
    disable_cache_storage
  end

  test "encoding" do
    tree_info = @tree_history.blame_tree
    refute_predicate tree_info, :empty?
    tree_info.each do |oid, path|
      assert_equal Encoding::UTF_8, oid.encoding
      assert_equal Encoding::ASCII_8BIT, path.encoding
    end
  end

  test "loading just tree entry data" do
    entries = @tree_history.tree_entries
    assert_equal 8, entries.size
    assert_includes entries.map(&:name), "README.txt"
    assert_includes entries.map(&:name), ".gitignore"
  end

  test "calculating all entry last commit information" do
    cached = @tree_history.cached_entry_commit_oids
    assert !cached.any? { |_k, v| v },
      "entries already in cache: #{cached.select { |_k, v| v }.inspect}"
    entries = @tree_history.calculate_all_entries
    assert_equal @tree_history.tree_entries.size, entries.size
    assert !entries.values.include?(nil)
  end

  test "loading cached latest commit for each tree entry" do
    @tree_history.calculate_all_entries

    commits = @tree_history.load_all_cached_entries
    tree_entries = @tree_history.tree_entries
    assert !tree_entries.empty?
    assert_equal tree_entries.size, commits.size

    paths = tree_entries.map(&:path)

    commits.each_key do |key|
      assert_includes paths, key
    end
  end

  test "calculates most recent commit for a path" do
    commit = @tree_history.load_or_calculate_single_entry("bin")
    assert commit.is_a?(Commit)
    assert_equal "634396b2f541a9f2d58b00be1a07f0c358b999b3", commit.oid
  end

  test "loads most recent commit for a path" do
    commit = @tree_history.load_or_calculate_single_entry("bin")
    assert commit.is_a?(Commit)
    assert_equal "634396b2f541a9f2d58b00be1a07f0c358b999b3", commit.oid
    assert_equal commit.oid, @tree_history.load_or_calculate_single_entry("bin").oid
  end

  test "calculates most recent commit for a sub path on a branch" do
    tree_history = @repo.directory(@repo.ref_to_sha("lazy_delegator"), path = "lib").tree_history
    commit = tree_history.load_or_calculate_single_entry("grit")
    assert commit.is_a?(Commit)
    assert_equal "4c596908ce1136e8c32174ba13892c6fe68a010d", commit.oid
  end

  test "loads most recent commit for a sub path on a branch" do
    tree_history = @repo.directory(@repo.ref_to_sha("lazy_delegator"), path = "lib").tree_history
    commit = tree_history.load_or_calculate_single_entry("grit")
    assert commit.is_a?(Commit)
    assert_equal "4c596908ce1136e8c32174ba13892c6fe68a010d", commit.oid
    assert_equal commit.oid, tree_history.load_or_calculate_single_entry("grit").oid
  end

  test "load_or_calculate_single_entry caches timeouts" do
    with_cache_enabled do
      @tree_history.repository.expects(:revision_list).raises(GitRPC::Timeout)
      tree_entry = @tree_history.tree_entries.detect { |entry| entry.name == "bin" }

      assert_raises GitRPC::Timeout do
        @tree_history.load_or_calculate_single_entry("bin")
      end
      assert_equal :_timeout, GitHub.cache.get(@tree_history.tree_entry_commit_key(tree_entry.path))
    end
  end

  test "load_or_calculate_single_entry raises if timeout cached" do
    with_cache_enabled do
      tree_entry = @tree_history.tree_entries.detect { |entry| entry.name == "bin" }

      GitHub.cache.set(@tree_history.tree_entry_commit_key(tree_entry.path), :_timeout)
      assert_raises GitRPC::Timeout do
        @tree_history.load_or_calculate_single_entry("bin")
      end
    end
  end

  test "load_all_cached_entries works with cached timeout" do
    with_cache_enabled do
      tree_entry = @tree_history.tree_entries.detect { |entry| entry.name == "bin" }

      GitHub.cache.set(@tree_history.tree_entry_commit_key(tree_entry.path), :_timeout)
      @tree_history.load_all_cached_entries
    end
  end

  test "doesn't try to load known bad paths" do
    @tree_history.stubs(:blame_tree).returns([])
    @tree_history.calculate_all_entries

    commit = @tree_history.load_or_calculate_single_entry("bin")
    assert_nil commit
  end

  test "returns an empty tree entry list for a bad path" do
    assert_raises(GitRPC::NoSuchPath) do
      @repo.directory(@repo.ref_to_sha("lazy_delegator"), path = "some/crap").tree_history
    end
  end

  test "returns an empty calculated tree entry hash for a bad path" do
    assert_raises(GitRPC::NoSuchPath) do
      @repo.directory(@repo.ref_to_sha("lazy_delegator"), path = "some/crap").tree_history
    end
  end

  test "requires entries to be passed on initialize" do
    assert_raises(ArgumentError) do
      TreeHistory.new(@repo, @repo.ref_to_sha("lazy_delegator"), "")
    end
  end

  test "over_max_tree_size? returns false if not over max tree size" do
    sha = @repo_with_over_limit_directory.ref_to_sha("master")
    path = "under_limit"
    directory = @repo_with_over_limit_directory.directory(sha, path)
    refute_predicate directory.tree_history, :over_max_tree_size?
  end

  test "over_max_tree_size? returns true if over max tree size" do
    sha = @repo_with_over_limit_directory.ref_to_sha("master")
    path = "over_limit"
    directory = @repo_with_over_limit_directory.directory(sha, path)
    assert_predicate directory.tree_history, :over_max_tree_size?
  end

  test "returns empty hash for calculate_all_entries if over max tree size" do
    sha = @repo_with_over_limit_directory.ref_to_sha("master")
    path = "over_limit"
    directory = @repo_with_over_limit_directory.directory(sha, path)
    assert_equal({}, directory.tree_history.calculate_all_entries)
  end

  test "returns empty hash for load_all_cached_entries if over max tree size" do
    sha = @repo_with_over_limit_directory.ref_to_sha("master")
    path = "over_limit"
    directory = @repo_with_over_limit_directory.directory(sha, path)
    assert_equal({}, directory.tree_history.load_all_cached_entries)
  end

  test "blame_tree result is empty upon CommandBusy" do
    Repository.any_instance.stubs(:blame_tree).raises(GitRPC::CommandBusy)
    assert_empty @tree_history.blame_tree
  end

  test "blame_tree raises upon non-timeout SpawnFailure" do
    ex = GitRPC::SpawnFailure.new(StandardError.new("hi"), [])
    Repository.any_instance.stubs(:blame_tree).raises(ex)
    assert_raises TreeHistory::TreeHistoryError do
      @tree_history.blame_tree
    end
  end

  test "blame_tree result is empty upon timeout SpawnFailure" do
    ex = GitRPC::SpawnFailure.new(GitRPC::Timer::Error.new("hi"), [])
    Repository.any_instance.stubs(:blame_tree).raises(ex)
    assert_empty @tree_history.blame_tree
  end

  test "blame_tree result is empty upon GitRPC::Timeout" do
    ex = GitRPC::Timeout.new
    Repository.any_instance.stubs(:blame_tree).raises(ex)
    assert_empty @tree_history.blame_tree
  end

  test "missing tree entry is handled" do
    expected_payload = {
      "SeverityText" => "WARN",
      "Body" => "Tree entry missing",
      "code.namespace" => "TreeHistory",
      "code.function" => "calculate_all_entries"
    }

    Repository.any_instance.stubs(:blame_tree).returns([
      ["invalidpath", "README.txt"],
    ])
    assert_logged(**expected_payload) do
      @tree_history.calculate_all_entries
    end
  end

  test "blame_tree logs argv upon GitRPC::Timeout" do
    e = GitRPC::Timeout.new("invalid command", argv: %w[hello world])
    expected_payload = {
      "exception.type" => "GitRPC::Timeout",
      "exception.message" => e,
      "code.namespace" => "TreeHistory",
      "code.function" => "blame_tree",
      "process.command_args" => /.+hello.+world.+/
    }
    assert_logged(**expected_payload) do
      Repository.any_instance.stubs(:blame_tree).raises(e)
      assert_empty @tree_history.blame_tree
    end
  end
end
