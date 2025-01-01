# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryGitDependencyTest < GitHub::TestCase
  include RepositoriesTestHelper

  CommitDataMock = Struct.new(:committed_at, :checksum, :error_message)
  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")
    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)

    @facebox  = create(:repository, name: "facebox",  owner: @defunkt)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)

    @nonexistant_network_id = 0
    snapshot_spokesdb
  end

  setup do
    @grit.update_default_branch("master")
  end

  context "#original_shard_path" do
    test "returns path to git data on disk" do
      assert_match /#{@simple.network.storage_path}\/#{@simple.id}\.git/, @simple.original_shard_path
    end

    test "raises UnroutedError if repo's network_id is nil" do
      @simple.update(network_id: nil)
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.original_shard_path
      end
    end

    test "raises UnroutedError if repo's network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.original_shard_path
      end
    end
  end

  context "#dgit_read_routes" do
    test "returns routes" do
      routes = @simple.dgit_read_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_read_routes
      end
    end

    test "never returns cache-replicas when running on non-cache-server" do
      orig_routes = @simple.dgit_read_routes
      refute_empty orig_routes
      host = orig_routes[0].fileserver.name
      GitHub::DGit::DB::FS::SQL.run("UPDATE fileservers SET cache_location = :cache_location WHERE host = :host", host: host, cache_location: "mars")
      @simple.dgit_reload_routes!

      non_cache_routes = @simple.dgit_read_routes
      assert_equal orig_routes.size - 1, non_cache_routes.size, "expected only non-cache routes by default"

      all_read_routes = @simple.dgit_read_routes(cache_servers_ok: true)
      assert_equal orig_routes.size - 1, all_read_routes.size, "expected only non-cache routes even when cache_servers_ok"
    end

    test "returns cache-replicas when running on cache-server, iff asked" do
      with_env({ "ENTERPRISE_CLUSTER_CACHE_LOCATION" => "mars" }) do
        orig_routes = @simple.dgit_read_routes
        refute_empty orig_routes

        empty_routes = @simple.dgit_read_routes(cache_servers_ok: true)
        assert_empty empty_routes, "expected no routes when asked for cache routes and there are none"

        host = orig_routes[0].fileserver.name
        GitHub::DGit::DB::FS::SQL.run("UPDATE fileservers SET cache_location = :cache_location WHERE host = :host", host: host, cache_location: "mars")
        @simple.dgit_reload_routes!

        non_cache_routes = @simple.dgit_read_routes
        assert_equal orig_routes.size - 1, non_cache_routes.size, "expected only non-cache routes by default"

        cache_routes = @simple.dgit_read_routes(cache_servers_ok: true)
        assert_equal 1, cache_routes.size, "expected only cache routes when asked"
        assert_equal host, cache_routes[0].fileserver.name, "cache route is on the cache host"

        fake_checksum = "5:0123456789abcdef0123456789abcdef01234567"
        fake_cache_checksum = "cache:#{fake_checksum}"

        GitHub::DGit::DB::FS::SQL.run("UPDATE repository_replicas SET checksum = :checksum WHERE host = :host AND repository_id = :repository_id AND repository_type = 0", checksum: fake_cache_checksum, host: host, repository_id: @simple.id)
        @simple.dgit_reload_routes!
        cache_routes = @simple.dgit_read_routes(cache_servers_ok: true)
        assert_equal 1, cache_routes.size, "expected only cache routes when asked, and cache checksum is stale"
        assert_equal host, cache_routes[0].fileserver.name, "cache route is on the cache host"

        GitHub::DGit::DB::FS::SQL.run("UPDATE repository_replicas SET checksum = :checksum WHERE host = :host AND repository_id = :repository_id AND repository_type = 0", checksum: fake_checksum, host: host, repository_id: @simple.id)
        @simple.dgit_reload_routes!
        cache_routes = @simple.dgit_read_routes(cache_servers_ok: true)
        assert_equal 1, cache_routes.size, "expected only cache routes when asked, and cache replica has a non-cache checksum"
        assert_equal host, cache_routes[0].fileserver.name, "cache route is on the cache host"
      end
    end
  end

  context "#dgit_wiki_read_routes" do
    test "returns routes" do
      @simple.initialize_wiki(@simple.owner)
      routes = @simple.dgit_wiki_read_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_wiki_read_routes
      end
    end
  end

  context "#dgit_write_routes" do
    test "returns routes" do
      routes = @simple.dgit_write_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_write_routes
      end
    end
  end

  context "#dgit_wiki_write_routes" do
    test "returns routes" do
      @simple.initialize_wiki(@simple.owner)
      routes = @simple.dgit_wiki_write_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_wiki_write_routes
      end
    end
  end

  context "#dgit_3pc_routes" do
    test "returns routes" do
      routes = @simple.dgit_3pc_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_3pc_routes
      end
    end
  end

  context "#dgit_all_routes" do
    test "returns routes" do
      routes = @simple.dgit_all_routes
      refute_empty routes
      routes.each do |route|
        assert_instance_of(GitHub::DGit::Route, route)
      end
    end

    test "raises UnroutedError if network doesn't exist" do
      @simple.update(network_id: @nonexistant_network_id) # simulate network that no longer exists
      assert_raises(GitHub::DGit::UnroutedError) do
        @simple.dgit_all_routes
      end
    end
  end

  context "refset_updated_at backfilling" do
    test "does nothing if the column is non-null" do
      ts = Time.current.round
      @grit.refset_updated_at = ts
      @grit.save!
      @grit.stubs(:backfill_refset_updated_at).raises(RuntimeError)
      assert_equal(ts, @grit.refset_updated_at) # implicit assertion that backfill wasn't called (it would blow up)
    end

    test "backfills to now if the column is null and no pushes to speak of" do
      now = Time.current.round
      travel_to now do
        @grit.refset_updated_at = nil
        @grit.save!
        assert_equal(now, @grit.refset_updated_at)
      end
    end

    test "backfills to now if pushes exist but none represent ref creation or deletion" do
      now = Time.current.round
      travel_to now do
        example_repo :simple, @grit
        @grit.refset_updated_at = nil
        @grit.save!
        head_commit = @grit.default_branch_ref.target
        push = create(:push,
          before: head_commit.first_parent_oid,
          after: head_commit.oid,
        )
        assert_equal(now, @grit.refset_updated_at)
      end
    end

    test "backfills to the push time if pushes exist that represent ref creation" do
      now = Time.current.round
      travel_to now do
        example_repo :simple, @grit
        @grit.refset_updated_at = nil
        @grit.save!
        head_commit = @grit.default_branch_ref.target
        push = create(:push,
          before: GitHub::NULL_OID,
          after: head_commit.oid,
        )
        assert_equal(push.pushed_at, @grit.refset_updated_at)
      end
    end

    test "backfills to the push time if pushes exist that represent ref deletion" do
      now = Time.current.round
      travel_to now do
        example_repo :simple, @grit
        @grit.refset_updated_at = nil
        @grit.save!
        head_commit = @grit.default_branch_ref.target
        push = create(:push,
          before: head_commit.oid,
          after: GitHub::NULL_OID,
          ref: "refs/heads/some_branch",
        )
        assert_equal(push.pushed_at, @grit.refset_updated_at)
      end
    end

    test "backfills to now if pushes exist but querying them triggers a database timeout" do
      now = Time.current.round
      travel_to now do
        example_repo :simple, @grit
        @grit.refset_updated_at = nil
        @grit.save!
        head_commit = @grit.default_branch_ref.target
        push = create(:push,
          before: head_commit.oid,
          after: GitHub::NULL_OID,
          ref: "refs/heads/some_branch",
        )
        Push.stubs(:order).raises(ActiveRecord::StatementTimeout)
        assert_equal(now, @grit.refset_updated_at)
      end
    end
  end

  test "is writable" do
    assert @grit.ready_for_writes?
    assert @ambition.ready_for_writes?
    assert @simple.ready_for_writes?
    assert @facebox.ready_for_writes?
  end

  test "is writable once created" do
    # Delete Spokes routes so the repo can go through unrouted and creating states.
    GitHub::DGit::Maintenance.delete_repo_replicas_and_checksums(@simple.network.id, @simple.id)

    # Since both empty? and creating? are memoized, we need to reload the repo
    # object from its ID if we want to check ready_for_writes? more than once.
    refute Repository.find_by!(id: @simple.id).ready_for_writes?
    @simple.initialize_replicas_from_network
    assert Repository.find_by!(id: @simple.id).creating?
    refute Repository.find_by!(id: @simple.id).ready_for_writes?
    @simple.create_git_repository_on_disk
    refute Repository.find_by!(id: @simple.id).creating?
    assert Repository.find_by!(id: @simple.id).ready_for_writes?

    all_replicas = GitHub::DGit::Routing.all_repo_replicas(@simple.id).select(&:voting?)
    _not_creating, *creating2 = all_replicas
    creating = creating2.first

    # When a quorum is not "creating", the repo is not creating.
    if GitHub.dgit_default_copies > 2
      ::DGit.set_repo_replica_checksum_for_host(@simple.network_id, "creating", creating.host)
      refute Repository.find_by!(id: @simple.id).creating?, "should not be creating when 1/#{all_replicas.size} replicas are 'creating'"
      assert Repository.find_by!(id: @simple.id).ready_for_writes?, "should be ready for writes when 1/#{all_replicas.size} replicas are 'creating'"
    end

    # When a quorum is "creating", the repo is too.
    if GitHub.dgit_default_copies > 1
      creating2.each do |rep|
        ::DGit.set_repo_replica_checksum_for_host(@simple.network_id, "creating", rep.host)
      end
      assert Repository.find_by!(id: @simple.id).creating?, "should be creating when #{creating2.size}/#{all_replicas.size} replicas are 'creating'"
      refute Repository.find_by!(id: @simple.id).ready_for_writes?, "should not be ready for writes when #{creating2.size}/#{all_replicas.size} replicas are 'creating'"
    end
  end

  context "#creating?" do
    test "raises NoVotingReplicas when no voting replicas exist" do
      repo = create(:repository, name: "repo", owner: @defunkt)
      DGit.adjust_replicas(repo, voting: 0, nonvoting: 3)
      assert_raises(GitHub::DGit::NoVotingReplicas) do
        Repository.find_by!(id: repo.id).creating?
      end
    end
  end

  test "#is_commit_in_branch_or_tag?" do
    example_repo :mojombo_grit, @grit

    branch = "temp_test_branch"
    tag    = "temp_test_tag"

    ref      = @grit.heads.create(branch, @grit.heads.find("master").target_oid, @grit.owner)
    metadata = { message: "test commit", committer: @grit.owner }
    commit   = ref.append_commit(metadata, @grit.owner) {}

    assert @grit.is_commit_in_branch_or_tag?(commit.oid)
    ref.delete(@grit.owner)
    refute @grit.is_commit_in_branch_or_tag?(commit.oid)

    ref = @grit.tags.create(tag, commit.oid, @grit.owner)
    assert @grit.is_commit_in_branch_or_tag?(commit.oid)
    ref.delete(@grit.owner)
    refute @grit.is_commit_in_branch_or_tag?(commit.oid)

    ref = @grit.extended_refs.create("refs/whatever", commit.oid, @grit.owner)
    refute @grit.is_commit_in_branch_or_tag?(commit.oid)
  end

  test "when updating the nwo file" do
    # Given an existing repository
    owner = create :user, login: "tpc-user"
    repo = create :repository, name: "tpc-target", owner: owner, from_example: :simple
    fake_checksum = "5:0123456789abcdef0123456789abcdef01234567"

    ::GitHub::Spokes::Proto::Repositories::V1::RepositoriesAPIClient.any_instance.stubs(:update_info_n_w_o).returns(
      Twirp::ClientResp.new(
        data: CommitDataMock.new(committed_at: 1711381577, checksum: fake_checksum),
        error: nil
      )
    )

    assert_nothing_raised do
      # When the nwo file is updated
      res = repo.update_nwo_file("foo/bar")

      # The the response payload should go through spokes-api and contain the
      # expected checksum from the mocked spokes call above.
      assert_equal fake_checksum, res[:checksum]
      assert_nil res[:error]
    end
  end

  context "#has_lfs_files?" do
    test "false for empty repo" do
      repo = create :repository
      refute repo.has_lfs_files?
    end

    test "false for simple repo without LFS files" do
      repo = create :repository, from_example: :simple
      refute repo.has_lfs_files?
    end

    test "true if repo has been pushed LFS files" do
      repo = create :repository, from_example: :git_lfs
      # :git_lfs is not enough, it only has LFS pointers
      # but it doesn't bring the blobs that those entries point to.
      create :media_blob, repository_network: repo.network

      assert repo.has_lfs_files?
    end
  end

  context "#tree_file_list" do
    test "excludes files from JUNK_DIRS" do
      assert_junk_excluded(repo_with_junk_dirs)
    end

    context "with .gitattributes file overriding JUNK_DIRS" do
      test "includes files from JUNK_DIRS" do
        repo = repo_with_junk_dirs
        add_overriding_gitattributes_file(repo)
        refute_junk_excluded(repo)
      end
    end

    context "with return_separate_lists set to true" do
      test "returns separate lists for files and directories" do
        assert_separate_lists_returned(repo_with_junk_dirs)
      end
    end
  end

  context "#includes_file?" do
    test "returns false if rpc throws InvalidRepository" do
      GitRPC::Client.any_instance.stubs(:read_tree_entry).raises(GitRPC::InvalidRepository)
      refute repo_with_junk_dirs.includes_file?(NEVER_JUNK_FILE)
    end
  end

  NEVER_JUNK_FILE = "whatever/path/not_junk"
  NEVER_JUNK_DIR = "whatever/path"
  POTENTIALLY_JUNK_VENDORED_FILE = "vendor/nested/path/maybe_junk"
  POTENTIALLY_JUNK_GENERATED_FILE = "build/other/nested/path/maybe_junk"

  def assert_junk_excluded(repo)
    list = repo.tree_file_list(repo.default_branch_ref.target.tree_oid)
    assert_includes list, NEVER_JUNK_FILE
    refute_includes list, POTENTIALLY_JUNK_VENDORED_FILE # potentially junk
    refute_includes list, POTENTIALLY_JUNK_GENERATED_FILE
  end

  def assert_separate_lists_returned(repo)
    list = repo.tree_file_list(repo.default_branch_ref.target.tree_oid, list_directories: true, return_separate_lists: true)
    assert_includes list[:files], NEVER_JUNK_FILE
    assert_includes list[:directories], NEVER_JUNK_DIR
  end

  def refute_junk_excluded(repo)
    list = repo.tree_file_list(repo.default_branch_ref.target.tree_oid)
    assert_includes list, NEVER_JUNK_FILE
    assert_includes list, POTENTIALLY_JUNK_VENDORED_FILE
    assert_includes list, POTENTIALLY_JUNK_GENERATED_FILE
  end

  def add_overriding_gitattributes_file(repo)
    repo.default_branch_ref.append_commit({ message: "gitattr", author: repo.owner }, repo.owner) do |files|
      files.add ".gitattributes", <<~GITATTRIBUTES
        vendor/** -linguist-vendored
        build/** -linguist-generated
      GITATTRIBUTES
    end
  end

  def repo_with_junk_dirs
    repo = create :repository, from_example: :simple
    repo.default_branch_ref.append_commit({ message: "files", author: repo.owner }, repo.owner) do |files|
      files.add(NEVER_JUNK_FILE, "1")
      files.add(POTENTIALLY_JUNK_VENDORED_FILE, "2")
      files.add(POTENTIALLY_JUNK_GENERATED_FILE, "3")
    end
    repo
  end
end
