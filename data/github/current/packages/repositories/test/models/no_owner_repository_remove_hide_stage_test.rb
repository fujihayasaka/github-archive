# typed: true
# frozen_string_literal: true

require "test_helper"

# This test case is for the in app (not background job) portion of the remove
# process. The repositories records are marked deleted = 1 and all remaining
# child forks reparented to maintain network consistency.
#
# See the separate archive and purge test case below for archiving
# and git repository on disk tests.
class NoOwnerRepositoryRemoveHideStageTest < GitHub::TestCase
  include HydroTestHelpers
  include RepositoriesTestHelper

  PackageRepoMock = Struct.new(:packages)
  fixtures do
    @priv_user = create(:user, plan: "medium")
    @pub_user = create(:user, plan: "medium")
    @user = create(:user)

    @private = create(:private_repository, owner: @priv_user, from_example: :simple)
    @private.add_member @pub_user
    @private.add_member @user

    @priv_fork = create(:fork_repository, forker: @pub_user, fork_repo: @private)

    @public = create(:repository, owner: @pub_user, from_example: :simple)
    @pub_fork = create(:fork_repository, forker: @priv_user, fork_repo: @public)

    METADATA_CLIENT = ::PackageRegistry::Twirp::MetadataClient
    example_repo_snapshot
  end

  setup do
    example_repo_restore
    METADATA_CLIENT.any_instance.stubs(:get_packages_by_repo).returns(PackageRepoMock.new(packages: []))
  end

  test "unsets active flag" do
    non_existent_owner(@public)
    @public.remove(@pub_user)

    refute @public.active?
  end

  test "allows same-name repo to be created" do
    @public.remove(@pub_user)

    repo = create(:repository, name: @public.name, owner: @pub_user)
    assert repo.valid?
  end

  test "sets deleted_by_user_id and deleted_at attributes" do
    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)
    assert_equal @pub_user.id, @public.deleted_by_user_id
    assert @public.deleted_at.is_a?(Time)

    record = Repositories::Public.find_deleted!(@public.id)
    assert_equal @pub_user.id, record.deleted_by_user_id
    assert_equal @pub_user, record.deleted_by
    assert record.deleted_at.is_a?(Time)
  end

  test "elects new root when existing root removed" do
    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)
    @pub_fork.reload
    assert @pub_fork.active?,        "bad cascading delete"
    assert @pub_fork.parent_id.nil?, "expected to be reparented to root"
  end

  if !GitHub.enterprise?
    test "emits a repository deleted event upon public repo removal for search indexing" do
      repo = create :repository, owner: @pub_user
      assert repo.active?

      non_existent_owner(repo)
      repo.remove(@pub_user, synchronous: true)

      refute repo.active?
      assert_equal @pub_user.id, repo.deleted_by_user_id

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(repo),
        ref: "refs/heads/#{repo.default_branch}",
        owner_name: repo.owner&.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
    end

    test "emits a repository deleted event upon private repo removal for search indexing" do
      assert @private.active?

      non_existent_owner(@private)

      # @private is the network root, so deleting it will also delete the child fork @priv_fork
      # that happens on a background job so make sure it runs
      @private.remove(@priv_user, synchronous: true)

      refute @private.active?
      assert_equal @priv_user.id, @private.deleted_by_user_id

      assert_hydro_messages(count: 2, schema: "github.search.v0.RepositoryChanged")

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(@private),
        ref: "refs/heads/#{@private.default_branch}",
        owner_name: @private.owner&.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

      @priv_fork.reload

      assert_hydro_published({
        change: :DELETED,
        repository: Hydro::EntitySerializer.repository(@priv_fork),
        ref: "refs/heads/#{@priv_fork.default_branch}",
        owner_name: @priv_fork.owner.name,
      }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)
    end
  end

  test "reparents remaining forks under remaining parent" do
    user2 = create(:user)
    fork2 = create(:fork_repository, forker: user2, fork_repo: @pub_fork)

    user3 = create(:user)
    fork3 = create(:fork_repository, forker: user3, fork_repo: @public)

    non_existent_owner(@pub_fork)
    @pub_fork.remove(user3, synchronous: true)
    fork2.reload
    fork3.reload
    assert_equal @public, fork2.parent
    assert_equal @public, fork3.parent
  end

  test "updates organization on reparented forks" do

    parent_org = create(:organization)
    parent_org.allow_private_repository_forking(actor: parent_org.admins.first)
    parent_team = create :team, organization: parent_org
    root_repo = create(:private_repository, owner: parent_org)
    assert parent_team.add_repository(root_repo, :pull).success?
    assert parent_team.add_member(@user).success?

    middle_org = create(:organization)
    middle_org.allow_private_repository_forking(actor: middle_org.admins.first)
    middle_team = create(:team, organization: middle_org, permission: "admin")
    assert middle_team.add_member(@user).success?

    middle_fork, status = root_repo.fork(forker: @user, org: middle_org)
    assert_equal :created, status
    assert middle_team.add_repository(middle_fork, :admin).success?

    user_fork, status = middle_fork.fork(forker: @user)
    assert_equal :created, status

    # sanity check:
    assert_equal middle_org.id, user_fork.organization_id

    # now, delete the middle repo:
    non_existent_owner(root_repo)
    middle_fork.remove(@user, synchronous: true)

    user_fork.reload
    assert_equal root_repo.id, user_fork.parent_id, "should be reparented"
    assert_equal parent_org.id, user_fork.organization_id
  end

  test "reparents remaining forks under newly elected root" do
    user2 = create(:user)
    fork2 = create(:fork_repository, forker: user2, fork_repo: @pub_fork)

    user3 = create(:user)
    fork3 = create(:fork_repository, forker: user3, fork_repo: @public)

    user4 = create(:user)
    fork4 = create(:fork_repository, forker: user4, fork_repo: fork2)

    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)

    @pub_fork.reload
    assert_nil @pub_fork.parent

    [fork2, fork3, fork4].each(&:reload)
    assert_equal @pub_fork, fork3.parent
    assert_equal @pub_fork, fork2.parent
    assert_equal fork2, fork4.parent
  end

  test "cascades to all same plan private forks when plan owner repo removed" do
    user2 = create(:user, plan: "medium")
    @priv_fork.add_member user2
    other_fork = create(:fork_repository, forker: @user, fork_repo: @private)

    fork2 = create(:fork_repository, forker: user2, fork_repo: @priv_fork)

    user3 = create(:user, plan: "medium")
    fork2.add_member user3
    fork3 = create(:fork_repository, forker: user3, fork_repo: fork2)
    forks = [@private, @priv_fork, fork2, fork3, other_fork]

    non_existent_owner(@private)
    @private.remove(@priv_user, synchronous: true)

    forks.each do |repo|
      repo.reload
      refute repo.active?, "private dependent #{repo} should be deleted"
    end
  end

  test "does not cascade to same plan private forks when fork is deleted" do
    user2 = create(:user, plan: "medium")
    @priv_fork.add_member user2
    fork2 = create(:fork_repository, forker: user2, fork_repo: @priv_fork)

    non_existent_owner(@private)
    @priv_fork.remove(user2, synchronous: true)
    refute @priv_fork.active?

    @private.reload
    assert @private.active?
    assert_nil @private.parent_id

    fork2.reload
    assert fork2.active?
    assert_equal @private, fork2.parent
  end

  test "promotes fork to root but not change the network" do
    assert_equal @public.id, @pub_fork.parent_id
    assert_equal @public.network_id, @pub_fork.network_id

    non_existent_owner(@public)
    @public.remove(@pub_user, synchronous: true)

    @pub_fork = Repositories::Public.find_active!(@pub_fork.id)
    assert_nil                 @pub_fork.parent_id
    assert_equal @pub_fork,    @pub_fork.root, "root was #{@public.inspect}"
    assert_equal @public.network_id,   @pub_fork.network_id
    assert_equal @pub_fork,    @pub_fork.network&.root
  end

  test "deleting private root with public forks reparents public forks" do
    @private.add_member(@user)
    repo = create(:fork_repository, forker: @user, fork_repo: @private)
    repo.toggle_visibility(actor: @user)
    assert repo.public?

    non_existent_owner(@private)
    @private.remove(@priv_user, synchronous: true)

    repo.reload
    assert_equal 1, repo.network_repositories.count
    assert_nil repo.parent_id
  end
end
