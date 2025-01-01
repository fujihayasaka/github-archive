# typed: false
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class RepositoryNetworkStorageTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, name: "mrowner", plan: "medium")
    @repo  = create(:repository, name: "network_test", owner: @owner)
    @repos = (1...2).map { |_num| create(:fork_repository, forker: create(:user), fork_repo: @repo) }
    @repos.last.update_attribute :pushed_at, Time.now + 100000
    @network = @repo.reload_network
  end

  setup do
    GitHub::DGit::Routing.hosts_for_network(@network.id).each do |host|
      path = GitHub::DGit.dev_route(@network.storage_path, host)
      assert_match %r{^#{GitHub.repository_root}/dgit\d+/.*/#{@network.id}$}, path
      FileUtils.rm_rf(path)
    end
    example_repo :forkable, @repo
  end

  def create_repositories
    repositories = [@repo] + @repos
    example_repo :simple, *repositories
    repositories.each(&:enable_shared_storage)
  end

  test "set_storage_attributes" do
    network = RepositoryNetwork.new(network_id: 8973272)

    network.set_storage_attributes

    assert_empty GitHub::DGit::Routing.all_network_replicas(network.id)
    assert network.needs_dgit_initialization_after_commit?
  end

  test "set_storage_attributes with non-voting target copies" do
    GitHub.dgit_non_voting_copies = 2
    ::DGit::add_fileserver(voting: false, embargoed: false, name: "dgit5")
    ::DGit::add_fileserver(voting: false, embargoed: false, name: "dgit6")
    ::DGit::add_fileserver(voting: false, embargoed: true,  name: "dgit7")

    network = RepositoryNetwork.new(network_id: 7354488)

    network.set_storage_attributes
    network.initialize_placeholder_network_replicas

    nrs = GitHub::DGit::Routing.all_network_replicas(network.id)
    assert_equal GitHub.dgit_default_copies + 2, nrs.length, "number of replicas"
    read_weights = Hash[nrs.map { |rep| [rep.host, rep.read_weight] }]
    refute_includes read_weights.keys, "dgit7", "shouldn't be placed on an embargoed host"
    assert_includes read_weights.keys, "dgit5"
    assert_includes read_weights.keys, "dgit6"
    assert_equal 0, read_weights["dgit5"], "dgit5 read weight"
    assert_equal 0, read_weights["dgit6"], "dgit6 read weight"
  end

  test "initialize_placeholder_network_replicas" do
    network = RepositoryNetwork.new(network_id: 8973272)

    network.set_storage_attributes
    assert network.needs_dgit_initialization_after_commit?

    network.initialize_placeholder_network_replicas
    assert_equal GitHub.dgit_default_copies, GitHub::DGit::Routing.all_network_replicas(network.id).length
  end

  test "set_saved_storage_attributes_with_replica_hosts" do
    network = RepositoryNetwork.new(network_id: 8973272)
    assert_raises(NoMethodError) { network.set_saved_storage_attributes_with_replica_hosts }
  end

  test "set_unsaved_storage_attributes_with_replica_hosts" do
    network = RepositoryNetwork.new(network_id: 8973272)
    assert_raises(NoMethodError) { network.set_unsaved_storage_attributes_with_replica_hosts }
  end

  test "storage_path" do
    assert_match %r{^#{GitHub.repository_root}/./nw/../../../#{@network.id}$},
      @network.storage_path
  end

  test "shared_storage_path" do
    assert_equal "#{@network.storage_path}/network.git", @network.shared_storage_path
  end

  test "shared_storage_enabled?" do
    assert !@network.rpc.exist?
    assert !@network.shared_storage_enabled?

    create_repositories
    assert @network.rpc.exist?
    assert @network.shared_storage_enabled?
  end

  test "disable_shared_storage" do
    create_repositories
    assert @network.rpc.exist?
    assert @network.shared_storage_enabled?

    @repo.disable_shared_storage
    assert !@repo.shared_storage_enabled?
  end

  test "repack" do
    create_repositories
    # Mock the repo as being previously collected
    @network.last_maintenance_at = Time.now

    res = @network.repack
    assert_match %r{git-repack completed}i, res["err"]
    assert @network.rpc.fs_exist?("info/nw-gc.log")
    assert res["err"].index(@network.rpc.fs_read("info/nw-gc.log"))
  end

  test "rpc" do
    assert_equal "ping", @network.rpc.echo("ping")
  end

  test "shard slack space is set to 0 in testing" do
    # mostly a sanity check so that *something* breaks if we refactor too hard
    # See: https://github.com/github/github/pull/27000#discussion_r13459750
    assert_equal 0, GitHub.shard_slack_space
  end

  test "calculate_disk_usage" do
    assert_nil @network.disk_usage

    create_repositories
    @network.calculate_disk_usage
    refute_nil @network.disk_usage
    @network.disk_usage = nil

    @network.calculate_disk_usage!
    @network.reload
    refute_nil @network.disk_usage
  end

  test "filling in disk usage when nil" do
    create_repositories

    assert_nil     @network.disk_usage
    refute_nil @network.disk_usage(true)

    val = @network.disk_usage + 10
    @network.disk_usage = val

    assert_equal val, @network.disk_usage
    assert_equal val, @network.disk_usage(true)
  end

  test "can calculate free space" do
    space = @network.calculate_free_space
    refute_nil space
    assert space.is_a?(Numeric)
    assert space > 0
  end
end
