# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryNetworkMaintenanceTest < GitHub::TestCase
  include HydroTestHelpers

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @owner = create(:user, name: "mrowner", plan: "medium")
    @repo  = create(:repository, name: "network_maintenance_test", owner: @owner, created_at: 2.days.ago)
    @priv = create(:fork_repository, forker: create(:user, plan: "medium"), fork_repo: @repo)

    # Mimic behavior of Repository#set_visibility!, which is now private
    @priv.stubs(:detach_on_visibility_change?).returns(false)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @priv.toggle_visibility(actor: @priv.owner)
    end

    @repos = [@repo, @priv] + Array.new(2) { create(:fork_repository, forker: create(:user), fork_repo: @repo) }
    @network = @repo.reload_network
    @networks = [@network] + Array.new(4) { create(:repository, owner: @owner).network }

    @min_age = 1.day

    # make all networks eligible for maintenance
    @networks.each_with_index do |network, i|
      network.update_column :last_maintenance_at, 2.days.ago + (i * 10)
      network.update_column :pushed_count_since_maintenance,  1
    end
  end

  setup do
    FileUtils.rm_rf(@network.storage_path)

    # fixture models in arrays are not reloaded automatically
    @networks.map! { |n| RepositoryNetwork.find(n.id) }
    @repos.map! { |r| Repositories::Public.get_active_or_deleted!(r.id) }

    @spawn_res_ok =     { "argv" => ["foo"], "out" => "", "ok" => true, "status" => 0, "err" => "sync: 92800494.git: +64K\nRunning git-repack" }
    @spawn_res_locked = { "argv" => ["foo"], "out" => "", "ok" => false, "status" => 2, "err" => "fatal: could not get the nw-sync lock. sync already in progress." }
  end

  test "find_most_active_since_last_maintenance triggered by push count and excluding non active networks" do
    @networks[0].update! pushed_count_since_maintenance: 1000
    @networks[1].update! pushed_count_since_maintenance: 500
    @networks[2].update! pushed_count_since_maintenance: 10

    networks = RepositoryNetwork.find_most_active_since_last_maintenance(@networks.size, 50, 20)
    assert_equal 2, networks.size
    assert_equal @networks[0], networks[0]
    assert_equal @networks[1], networks[1]
  end

  test "find_most_active_since_last_maintenance triggered by push size and excluding non active networks" do
    @networks[0].update! pushed_count_since_maintenance: 1, unpacked_size_in_mb: 1000
    @networks[1].update! pushed_count_since_maintenance: 1, unpacked_size_in_mb: 50
    @networks[2].update! pushed_count_since_maintenance: 1, unpacked_size_in_mb: 30
    @networks[3].update! pushed_count_since_maintenance: 1, unpacked_size_in_mb: 10

    networks = RepositoryNetwork.find_most_active_since_last_maintenance(@networks.size, 50, 40)
    assert_equal 2, networks.size
    assert_equal @networks[0], networks[0]
    assert_equal @networks[1], networks[1]
  end

  test "find_most_active_since_last_maintenance excluding failed, scheduled, running networks" do
    @networks[0].update! maintenance_status: "scheduled", pushed_count_since_maintenance: 1000
    @networks[1].update! maintenance_status: "running",   pushed_count_since_maintenance: 1000
    @networks[2].update! maintenance_status: "failed",    pushed_count_since_maintenance: 1000
    @networks[3].update! maintenance_status: "complete",  pushed_count_since_maintenance: 1000
    @networks[4].update! maintenance_status: "complete",  pushed_count_since_maintenance: 5000

    networks = RepositoryNetwork.find_most_active_since_last_maintenance(@networks.size, 50, 20)
    assert_equal 2, networks.size
    assert_equal @networks[4], networks[0]
    assert_equal @networks[3], networks[1]
  end

  test "move_stuck_networks_to_retry! moves as expected" do
    @networks[0].update! maintenance_status: "scheduled", last_maintenance_attempted_at: Time.now - 2.days
    @networks[1].update! maintenance_status: "scheduled", last_maintenance_attempted_at: Time.now
    @networks[2].update! maintenance_status: "failed"
    @networks[3].update! maintenance_status: "complete"

    nnetworks = RepositoryNetwork.move_stuck_networks_to_retry!(RepositoryNetwork)
    expected = [@networks[0].clone.tap { |g| g.maintenance_status = "retry" }]
    assert_equal 1, nnetworks
    assert_same_elements expected, RepositoryNetwork.where(maintenance_status: :retry)
  end

  test "move_orphaned_networks_to_broken! moves as expected" do
    @networks[0].update! maintenance_status: "retry", last_maintenance_attempted_at: Time.now - 2.days
    @networks[1].update! maintenance_status: "retry", last_maintenance_attempted_at: Time.now
    @networks[2].update! maintenance_status: "retry", last_maintenance_attempted_at: Time.now - 2.days
    @networks[3].update! maintenance_status: "retry", last_maintenance_attempted_at: Time.now - 1.day
    @networks[4].update! maintenance_status: "retry", last_maintenance_attempted_at: Time.now - 2.days

    # This network has multiple repositories.
    @networks[0].root.delete
    # This network isn't stale.
    @networks[1].root.delete
    # These networks should be pruned.
    @networks[3].root.delete
    @networks[4].root.delete

    nnetworks = RepositoryNetwork.move_orphaned_networks_to_broken!
    expected = [
      @networks[3].clone.tap { |g| g.maintenance_status = "broken" },
      @networks[4].clone.tap { |g| g.maintenance_status = "broken" },
    ]
    assert_same_elements expected, RepositoryNetwork.where(maintenance_status: :broken)
    assert_equal 2, nnetworks
  end

  test "updating maintenance_status" do
    assert_raises ActiveRecord::RecordInvalid do
      @network.update_status(:nope)
    end

    @network.update_status(:scheduled)
    assert_equal "scheduled", @network.maintenance_status
    assert @network.maintenance_pending?

    @network.update_status(:running)
    assert_equal "running", @network.maintenance_status
    assert @network.maintenance_pending?

    @network.update_status(:complete)
    assert_equal "complete", @network.maintenance_status
    refute @network.maintenance_pending?

    @network.update_status(:failed)
    assert_equal "failed", @network.maintenance_status
    refute @network.maintenance_pending?

    @network.maintenance_status = :complete
    refute @network.maintenance_pending?

    @network.save!
  end


  test "maintenance_queue_name" do
    first_host = GitHub::DGit::Routing.hosts_for_network(@network.id).first
    assert_equal "maint_#{first_host}", @network.maintenance_queue_name.value!
  end

  test "schedule_maintenance" do
    assert_enqueued_jobs 1, queue: @network.maintenance_queue_name.value! do
      @network.schedule_maintenance
      @network.reload
      assert_equal "scheduled", @network.maintenance_status
    end
  end

  def create_git_repositories
    reset_repo_root
    other = @repos.last
    example_repo :simple, *(@repos - [other])
    example_repo :refs_test, other
    @repos.each(&:enable_or_disable_shared_storage)
  end

  def list_files(repo, pattern)
    path = if repo.class == Repository
      repo.dgit_all_routes[0].path
    elsif repo.class == RepositoryNetwork
      repo.dgit_mapped_shared_storage_path
    else
      fail "I have no idea what kind of object this is"
    end

    Dir["#{path}/#{pattern}"].sort
  end

  test "perform_maintenance visits non-alternated repositories" do
    create_git_repositories

    @network.update_attribute :last_maintenance_at, 1.day.ago
    @priv.update_attribute :pushed_at, Time.now

    assert_equal 1, list_files(@priv, "objects/pack/*.pack").size
    assert_equal 0, list_files(@priv, "objects/pack/*.bitmap").size

    # generate some objects and repack to build a new pack
    parent = @priv.rpc.rev_parse("refs/heads/master")
    5.times do |num|
      commit = {
        "message"   => "stuff",
        "committer" => { "name" => "joe committer", "email" => "joe@somewhere.com" },
      }
      files = { "some-file #{num}" => "some data #{num}\n" }
      parent = @priv.rpc.create_tree_changes(parent, commit, files)
      RefUpdater.update_ref(@priv, "refs/heads/master", parent)
    end
    @priv.rpc.repack # would raise on error

    assert_equal 2, list_files(@priv, "objects/pack/*.pack").size
    assert_equal 0, list_files(@priv, "objects/pack/*.bitmap").size
    assert list_files(@priv, "refs/heads/master").any?

    @network.perform_maintenance

    # verify repack and pack-refs
    assert_equal 1, list_files(@priv, "objects/pack/*.pack").size
    assert list_files(@priv, "refs/heads/master").empty?
    assert_equal 1, list_files(@priv, "objects/pack/*.bitmap").size

    hydro_payload = hydro_messages(schema: "git.v1.Maintenance").first
    assert_equal(@network.id, hydro_payload[:network_id])
    assert_equal(4, hydro_payload[:repository_count])
    assert_equal(true, hydro_payload[:is_geometric_repack])
    assert_equal(true, hydro_payload[:is_shared_storage_enabled])
    assert(hydro_payload[:repack_duration_in_seconds] > 0.0)
  end

  test "perform_maintenance runs a repack in non-alternated repos regardless of pushed_at state" do
    standalone_repo = create(:repository, name: "repo_maintenance_test", owner: @owner, created_at: 2.days.ago, from_example: :simple)
    standalone_repo_network = standalone_repo.reload_network


    assert_equal 1, list_files(standalone_repo, "objects/pack/*.pack").size
    assert_equal 0, list_files(standalone_repo, "objects/pack/*.bitmap").size

    # Run a first maintenance
    standalone_repo.update_attribute(:pushed_at, 1.hour.ago)
    standalone_repo_network.perform_maintenance

    assert_equal 2, list_files(standalone_repo, "objects/pack/*.pack").size
    assert_equal 1, list_files(standalone_repo, "objects/pack/*.bitmap").size

    # generate some objects
    parent = standalone_repo.rpc.rev_parse("refs/heads/master")
    5.times do |num|
      commit = {
          "message"   => "stuff",
          "committer" => { "name" => "joe committer", "email" => "joe@somewhere.com" },
      }
      files = { "some-file #{num}" => "some data #{num}\n" }
      parent = standalone_repo.rpc.create_tree_changes(parent, commit, files)
      RefUpdater.update_ref(standalone_repo, "refs/heads/master", parent)
    end

    # We should have a loose ref after updating it
    assert list_files(standalone_repo, "refs/heads/master").any?

    standalone_repo_network.perform_maintenance

    # After repacking we should have three pack(s) with a bitmap file and no
    # loose refs
    assert_equal 3, list_files(standalone_repo, "objects/pack/*.pack").size
    assert_equal 1, list_files(standalone_repo, "objects/pack/*.bitmap").size
    assert list_files(standalone_repo, "refs/heads/master").empty?

    hydro_payload = hydro_messages(schema: "git.v1.Maintenance").first
    assert_equal(standalone_repo_network.id, hydro_payload[:network_id])
    assert_equal(1, hydro_payload[:repository_count])
    assert_equal(true, hydro_payload[:is_geometric_repack])
    assert_equal(false, hydro_payload[:is_shared_storage_enabled])
    assert(hydro_payload[:repack_duration_in_seconds] > 0.0)
  end

  test "perform_maintenance succeeds on non-existing repositories" do
    create_git_repositories

    repo_path = @priv.shard_path
    @priv.rpc.remove
    assert !File.exist?(repo_path)

    @network.perform_maintenance

    @network.reload
    assert_equal "complete", @network.maintenance_status
  end

  test "perform_maintenance links forks" do
    skip unless GitHub.dgit_default_copies > 1
    create_git_repositories

    # revert to public, or enable_shared_storage will fail
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
      @priv.toggle_visibility(actor: @priv.owner)
    end

    # Move objects back into a the @priv fork, and delete both
    # network.git and objects/info/alternates. First GC so we don't
    # have to worry about loose objects:
    @repo.rpc.nw_gc

    path = @repo.shard_path
    FileUtils.rm_r("#{path}/objects/pack")
    File.rename("#{path}/../network.git/objects/pack", "#{path}/objects/pack")
    FileUtils.rm_r("#{path}/../network.git")
    File.unlink("#{path}/objects/info/alternates")
    assert !File.exist?("#{path}/../network.git/objects/pack")
    assert !File.exist?("#{path}/objects/info/alternates")

    @network.perform_maintenance

    # Ensure that the fork is once again linked
    assert File.exist?("#{path}/../network.git/objects/pack")
    assert File.exist?("#{path}/objects/info/alternates")
  end

  test "perform_maintenance repacks and builds bitmaps in shared network.git storage" do
    create_git_repositories

    assert_equal 2, list_files(@network, "objects/pack/*.pack").size
    assert_equal 0, list_files(@network, "objects/pack/*.bitmap").size
    assert list_files(@network, "refs/remotes/*/heads/*").size > 5

    @network.perform_maintenance

    # verify repack and pack-refs
    assert_equal 3, list_files(@network, "objects/pack/*.pack").size
    assert_equal 1, list_files(@network, "objects/pack/*.bitmap").size
    assert_equal 0, list_files(@network, "refs/remotes/*/heads/*").size
  end

  def verify_maintenance_loop(n)
    seq = sequence("nw_gc")
    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(geometric: true)).times(n).in_sequence(seq)
    ::GitRPC::Client.any_instance.expects(:nw_gc)
      .with(has_entry(geometric: false)).once.in_sequence(seq)

    n.times do |i|
      @network.perform_maintenance

      assert_equal "complete", @network.maintenance_status
      assert_equal i + 1, @network.maintenance_count_since_full
    end

    @network.perform_maintenance
    assert_equal "complete", @network.maintenance_status
    assert_equal 0, @network.maintenance_count_since_full
  end

  test "perform_maintenance alternates between geometric and full repacks" do
    create_git_repositories

    verify_maintenance_loop(32)
  end

  test "schedule failed networks" do
    @networks[0].update! pushed_count: 1, disk_usage: 3, maintenance_status: "failed"
    @networks[1].update! pushed_count: 2, disk_usage: 2, maintenance_status: "failed"
    @networks[2].update! pushed_count: 3, disk_usage: 1, maintenance_status: "failed"

    res = RepositoryNetwork.find_failed_networks(10, :pushed_count)
    assert_equal [@networks[2], @networks[1], @networks[0]], res

    res = RepositoryNetwork.find_failed_networks(10, :disk_usage)
    assert_equal [@networks[0], @networks[1], @networks[2]], res

    assert_raises(ArgumentError) do
      RepositoryNetwork.find_failed_networks(10, :specific_gravity)
    end

    assert_enqueued_jobs 3 do
      RepositoryNetwork.schedule_maintenance_retries
    end
  end

  test "excluding hosts with large schedule backlogs - DGit" do
    zap_host = (GitHub::DGit.get_hosts - GitHub::DGit::Routing.hosts_for_network(@networks.last.id)).first
    @networks.each do |network|
      network.update! pushed_count_since_maintenance: 51
    end
    @networks[0].update_column :maintenance_status, "scheduled"
    nrs = GitHub::DGit::Routing.all_network_replicas(@networks[0].id)
    nrs.each_with_index do |nr, i|
      nr_id = ::DGit::get_network_replica_id_for_host(@networks[0].id, nr.host)
      if i == nrs.size - 1
        ::DGit::update_network_replica_host(@networks[0].id, nr_id, zap_host)
      else
        ::DGit::update_network_replica_host(@networks[0].id, nr_id, "dgit-fake-#{i}")
      end
    end

    # Can't use `all_network_replicas` here, which joins against `fileservers`.
    expected_hosts = GitHub::DGit::DB.for_network_id(@networks[0].id).SQL.values(
      "SELECT host FROM network_replicas WHERE network_id = :network_id",
      network_id: @networks[0].id)
    exclusions = RepositoryNetwork.scheduled_maintenance_exclusions(limit = 1)
    assert_same_elements expected_hosts, exclusions

    expect_count = @networks.count do |n|
      !GitHub::DGit::Routing.all_network_replicas(n.id).map(&:host).include?(zap_host)
    end

    assert_enqueued_jobs expect_count do
      RepositoryNetwork.schedule_maintenance(@networks.size, host_threshold = 1, @min_age)
    end
  end

  test "creating a network sets last maintenance to created_at" do
    Timecop.freeze do
      new_repo = create(:repository, name: "network_last_maintenance_timestamp", owner: @owner)
      network = new_repo.reload_network
      assert_equal network.created_at, network.last_maintenance_at
      assert_equal "complete", network.maintenance_status
    end
  end

  test "running maintenance is retried on spurious failures" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:get_maint_size).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: true }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
  end

  test "running maintenance on network with spurious errors will mark it failed if we fail more than three times" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:get_maint_size).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: true }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance("spurious_failure")
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance("spurious_failure")
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance("spurious_failure")
    end
    assert_equal "failed", @network.attributes["maintenance_status"]
  end

  test "running maintenance is retried when there's not enough space free" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:get_maint_size).returns(1_000_000_000)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "running maintenance is retried when one replica is FAILED" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    host = GitHub::DGit::Routing.hosts_for_network(@network.id).first
    GitHub::DGit::Maintenance.set_network_state(@network.id, host, GitHub::DGit::FAILED)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "running maintenance is retried when one backend is locked" do
    @repo.enable_shared_storage
    assert_equal "complete", @network.attributes["maintenance_status"]
    Repository.any_instance.stubs(:repack)
    @network.stubs(:enough_space_to_run_maintenance?).returns(true)
    @network.stubs(:calculate_disk_usage!)
    ::GitRPC::Backend.any_instance.stubs(:spawn).returns(@spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok, @spawn_res_locked, @spawn_res_ok)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "running maintenance is retried in the unlikely event that all backends are locked" do
    @repo.enable_shared_storage
    assert_equal "complete", @network.attributes["maintenance_status"]
    Repository.any_instance.stubs(:repack)
    @network.stubs(:enough_space_to_run_maintenance?).returns(true)
    @network.stubs(:calculate_disk_usage!)
    ::GitRPC::Backend.any_instance.stubs(:spawn).returns(@spawn_res_locked)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "running maintenance fails when we can't estimate maintenance size" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:get_maint_size).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: true }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
  end

  test "repository with corruption that we can't fix is marked as spurious failure" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: false }.stringify_keys).then.returns({ ok: true }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects)
      .returns({ ok: false, status: 1 }.stringify_keys)
      .then.returns({ ok: true, status: 0 }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
  end

  test "maintenance on repository repository with fixed corruption will be retried" do
    @repo.enable_shared_storage
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_gc).raises(::GitRPC::Error)
    ::GitRPC::Backend.any_instance.stubs(:nw_fsck).returns({ ok: false }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects).returns({ ok: true, err: "1 object was restored" }.stringify_keys)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "non-alternated repository with unfixable corruption is marked as spurious failure" do
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    ::GitRPC::Client.any_instance.stubs(:nw_fsck)
           .returns({ ok: true }.stringify_keys)  # skip the first nw_fsck (of the network, in network_corrupt?)
      .then.returns({ ok: false }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects).returns({ ok: true }.stringify_keys)
    assert_raises(::GitRPC::Error) do
      @network.perform_maintenance
    end
    assert_equal "spurious_failure", @network.attributes["maintenance_status"]
  end

  test "maintenance on non-alternated repository with fixed corruption will be retried" do
    @repo.enable_shared_storage
    assert_equal "complete", @network.attributes["maintenance_status"]
    ::GitRPC::Backend.any_instance.stubs(:nw_repack).raises(::GitRPC::Error)
    ::GitRPC::Client.any_instance.stubs(:nw_fsck)
           .returns({ ok: true }.stringify_keys)  # skip the first nw_fsck (of the network, in network_corrupt?)
      .then.returns({ ok: false }.stringify_keys)
    ::GitRPC::Backend.any_instance.stubs(:restore_objects).returns({ ok: true, err: "2 objects were restored" }.stringify_keys)
    @network.perform_maintenance
    assert_equal "retry", @network.attributes["maintenance_status"]
  end

  test "mark_as_broken creates an audit log entry" do
    events = subscribe "repository_network.mark_as_broken"

    @network.mark_as_broken

    expected_payload = {
      public_repo: @network.root.public?,
      repository_network_id: @network.id,
      repository_network: @network.name,
    }

    assert event = events.pop, "an repository_network.mark_as_broken event was expected"
    assert_equal "repository_network.mark_as_broken", event.name
    assert_equal expected_payload, event.payload
  end
end
