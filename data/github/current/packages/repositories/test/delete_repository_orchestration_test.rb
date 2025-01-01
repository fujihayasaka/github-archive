# typed: true
# frozen_string_literal: true

require "test_helper"

class DeleteRepositoryOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include HookIntegrationTestHelper

  fixtures do
    @owner = create(:user, name: "rootowner")
    @user1 = create(:user, name: "user1")
    @user2 = create(:user, name: "user2")
    @user3 = create(:user, name: "user3")
    @user4 = create(:user, name: "user4")
    @user5 = create(:user, name: "user5")

    # create a public network
    @pub_root = create(:public_repository, name: "public", owner: @owner)
    @pub_fork1, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_root.fork(forker: @user1) }
    @pub_fork2, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_root.fork(forker: @user2) }
    @pub_fork4, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_fork1.fork(forker: @user4) }
    @pub_fork5, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_fork1.fork(forker: @user5) }

    # create a private network
    @priv_root = create(:private_repository, name: "private", owner: @owner)
    @priv_root.add_member(@user1)
    @priv_root.add_member(@user2)
    @priv_root.add_member(@user4)
    @priv_fork1, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_root.fork(forker: @user1) }
    @priv_fork2, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_root.fork(forker: @user2) }
    @priv_fork1.add_member(@user5)
    @priv_fork4, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_fork1.fork(forker: @user4) }
    @priv_fork5, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_fork1.fork(forker: @user5) }

    # create an internal network
    @org = create(:organization, name: "org", plan: GitHub::Plan.business_plus, admins: [@owner], seats: 20)
    @org1 = create(:organization, name: "org1", plan: GitHub::Plan.business_plus, admins: [@user1], seats: 20)
    @org2 = create(:organization, name: "org2", plan: GitHub::Plan.business_plus, admins: [@user2], seats: 20)
    @biz = create(:business, name: "biz", owners: [@owner, @user1, @user2], organizations: [@org, @org1, @org2], seats: 20)
    @org.reload
    @org1.reload
    @org2.reload
    @org.allow_private_repository_forking(actor: @owner)
    @org1.allow_private_repository_forking(actor: @user1)
    @org2.allow_private_repository_forking(actor: @user2)
    @int_root = create :internal_repository, private: true, name: "internal", owner: @org
    @org1.allow_private_repository_forking(actor: @user1)

    @int_fork1, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @int_root.fork(forker: @user1, org: @org1) }
    @int_fork2, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @int_root.fork(forker: @user2, org: @org2) }

    # create a mixed network of public, private, public
    @pub_priv_root = create(:public_repository, name: "public-private", owner: @owner)
    @pub_priv_fork1, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_priv_root.fork(forker: @user1) }
    @pub_priv_fork2, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_priv_root.fork(forker: @user2) }
    @pub_priv_fork3, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_priv_root.fork(forker: @user3) }
    @pub_priv_fork4, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_priv_fork1.fork(forker: @user4) }
    @pub_priv_fork5, _ = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @pub_priv_fork1.fork(forker: @user5) }
    @pub_priv_fork1.set_visibility(actor: @pub_priv_fork1.owner, visibility: "private")
    @pub_priv_fork2.set_visibility(actor: @pub_priv_fork2.owner, visibility: "private")

    # create a mixed network of private, public, private
    @priv_pub_root = create(:private_repository, name: "private-public", owner: @owner)
    @priv_pub_root.add_member(@user1)
    @priv_pub_root.add_member(@user2)
    @priv_pub_root.add_member(@user3)
    @priv_pub_root.add_member(@user4)
    @priv_pub_fork1, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_pub_root.fork(forker: @user1) }
    @priv_pub_fork1.errors.clear
    @priv_pub_fork2, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_pub_root.fork(forker: @user2) }
    @priv_pub_fork2.errors.clear
    @priv_pub_fork3, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_pub_root.fork(forker: @user3) }
    @priv_pub_fork1.add_member(@user5)
    @priv_pub_fork4, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_pub_fork1.fork(forker: @user4) }
    @priv_pub_fork5, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_pub_fork1.fork(forker: @user5) }
    @priv_pub_fork1.set_visibility(actor: @priv_pub_fork1.owner, visibility: "public")
    @priv_pub_fork2.set_visibility(actor: @priv_pub_fork2.owner, visibility: "public")

    # create a mixed network of private, private, public
    @priv_priv_root = create(:private_repository, name: "private-private", owner: @owner)
    @priv_priv_root.add_member(@user1)
    @priv_priv_fork1, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_priv_root.fork(forker: @user1) }
    @priv_priv_fork1.add_member(@user2)
    @priv_priv_fork1.add_member(@user3)
    @priv_priv_fork1.add_member(@user4)
    @priv_priv_fork1.add_member(@user5)
    @priv_priv_fork2, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_priv_fork1.fork(forker: @user2) }
    @priv_priv_fork2.errors.clear
    @priv_priv_fork3, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_priv_fork1.fork(forker: @user3) }
    @priv_priv_fork3.errors.clear
    @priv_priv_fork4, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_priv_fork1.fork(forker: @user4) }
    @priv_priv_fork4.errors.clear
    @priv_priv_fork5, message = perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @priv_priv_fork1.fork(forker: @user5) }
    @priv_priv_fork5.errors.clear
    @priv_priv_fork4.set_visibility(actor: @priv_priv_fork4.owner, visibility: "public")
    @priv_priv_fork5.set_visibility(actor: @priv_priv_fork5.owner, visibility: "public")
  end

  setup do
    # preload this to prevent flakiness with query counts when running the test in gauntlet
    GitHub.never_delete_ids
  end

  test "delete private root" do
    network_id = @priv_root.network.id
    o = delete_repo @priv_root

    assert @priv_root.reload.deleted?
    assert @priv_fork1.reload.deleted?
    assert @priv_fork2.reload.deleted?
    assert @priv_fork4.reload.deleted?
    assert @priv_fork5.reload.deleted?

    assert_equal network_id, @priv_root.network.id
    assert_equal network_id, @priv_fork1.network.id
    assert_equal network_id, @priv_fork2.network.id
    assert_equal network_id, @priv_fork4.network.id
    assert_equal network_id, @priv_fork5.network.id

    assert_equal @priv_root.id, @priv_root.network.root.id
  end

  test "remove permissions to private fork" do
    # user1 loses permissions to the root, which results in its fork getting deleted
    @priv_root.remove_member(@user1)
    o = delete_repo(@priv_fork1, delete_forks_inaccessible_to: @priv_fork1.parent.id)

    # the root in unaffected
    assert @priv_root.reload.active?

    # fork1 gets deleted
    assert @priv_fork1.reload.deleted?
    assert_equal @priv_root.id, @priv_fork1.parent.id

    # fork2 is unaffected by its sibling fork1 being deleted
    assert @priv_fork2.reload.active?
    assert_equal @priv_root.id, @priv_fork2.parent.id

    # fork4 is a child of fork1, but it has access to priv_root, so it can stay
    assert @priv_fork4.reload.active?
    assert_equal @priv_root.id, @priv_fork4.parent.id

    # fork5 is a child of fork1, and only had access to fork1, so it gets deleted
    assert @priv_fork5.reload.deleted?
    assert_equal @priv_fork1.id, @priv_fork5.parent.id
  end

  test "delete private fork" do
    network_id = @priv_root.network.id
    assert_equal @priv_fork1.id, @priv_fork4.parent.id
    assert_equal @priv_root.network.id, @priv_fork4.network.id

    o = delete_repo @priv_fork1

    assert @priv_root.reload.active?
    assert @priv_fork1.reload.deleted?
    assert @priv_fork2.reload.active?
    assert @priv_fork4.reload.active?
    assert @priv_fork5.reload.active?

    assert_equal @priv_root.id, @priv_fork4.parent.id

    assert_equal network_id, @priv_root.network.id
    assert_equal network_id, @priv_fork1.network.id
    assert_equal network_id, @priv_fork2.network.id
    assert_equal network_id, @priv_fork4.network.id
    assert_equal network_id, @priv_fork5.network.id

    assert_equal @priv_root.id, @priv_root.network.root.id
  end

  test "delete public root" do
    network_id = @pub_root.network.id

    o = delete_repo @pub_root

    assert @pub_root.reload.deleted?
    assert @pub_fork1.reload.active?
    assert @pub_fork2.reload.active?
    assert @pub_fork4.reload.active?
    assert @pub_fork5.reload.active?

    assert_nil @pub_fork1.parent
    assert_equal @pub_fork1.id, @pub_fork2.parent.id
    assert_equal @pub_fork1.id, @pub_fork4.parent.id

    assert_equal network_id, @pub_root.network.id
    assert_equal network_id, @pub_fork1.network.id
    assert_equal network_id, @pub_fork2.network.id
    assert_equal network_id, @pub_fork4.network.id
    assert_equal network_id, @pub_fork5.network.id

    assert_equal @pub_fork1.id, @pub_fork1.network.root.id
  end

  test "delete public fork" do
    network_id = @pub_root.network.id
    assert_equal @pub_fork1.id, @pub_fork4.parent.id
    assert_equal @pub_root.network.id, @pub_fork4.network.id

    o = delete_repo @pub_fork1

    assert @pub_root.reload.active?
    assert @pub_fork1.reload.deleted?
    assert @pub_fork2.reload.active?
    assert @pub_fork4.reload.active?
    assert @pub_fork5.reload.active?

    assert_equal @pub_root.id, @pub_fork4.parent.id
    assert_equal network_id, @pub_root.network.id
    assert_equal network_id, @pub_fork1.network.id
    assert_equal network_id, @pub_fork2.network.id
    assert_equal network_id, @pub_fork4.network.id
    assert_equal network_id, @pub_fork5.network.id

    assert_equal @pub_root.id, @pub_root.network.root.id
  end

  test "delete private root of mixed network" do
    network_id = @priv_pub_root.network.id

    o = delete_repo @priv_pub_root

    assert @priv_pub_root.reload.deleted?
    assert @priv_pub_fork1.reload.active?
    assert @priv_pub_fork2.reload.active?
    # fork3, fork4, fork5 get deleted because they are private and the root is private
    assert @priv_pub_fork3.reload.deleted?
    assert @priv_pub_fork4.reload.deleted?
    assert @priv_pub_fork5.reload.deleted?

    # public fork1 should be the root of the network
    assert_equal network_id, @priv_pub_fork1.network.id
    assert_equal @priv_pub_fork1.id, @priv_pub_fork1.network.root.id
    assert_nil   @priv_pub_fork1.parent
    assert_equal "public", @priv_pub_fork1.visibility

    # public fork2 should be a child of fork1 now
    assert_equal network_id, @priv_pub_fork2.network.id
    assert_equal @priv_pub_fork1.id, @priv_pub_fork2.network.root.id
    assert_equal @priv_pub_fork1.id, @priv_pub_fork2.parent&.id
    assert_equal "public", @priv_pub_fork2.visibility
  end

  test "delete private fork of public root parent" do
    network_id = @pub_priv_root.network.id

    o = RepositoryOrchestration.delete(@pub_priv_fork1, actor: User.ghost)

    reparent_ids = o.send(:fork_ids_to_reparent)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { o.execute }
    o.reload

    assert @pub_priv_root.reload.active?
    assert @pub_priv_fork1.reload.deleted?
    assert @pub_priv_fork2.reload.active?
    assert @pub_priv_fork3.reload.active?
    assert @pub_priv_fork4.reload.active?
    assert @pub_priv_fork5.reload.active?

    # the public root should be unchanged
    # private fork2 should be unchanged in the remaining mixed network
    assert       @pub_priv_fork2.network.id == network_id
    assert_equal @pub_priv_root.id, @pub_priv_fork2.network.root.id
    assert_equal "private", @pub_priv_fork2.visibility

    # public fork3 should be unchanged
    assert_equal network_id, @pub_priv_fork3.network.id
    assert_equal @pub_priv_root.id, @pub_priv_fork3.network.root.id
    assert_equal "public", @pub_priv_fork3.visibility

    # fork4 is public but should get reparented to its public grandparent
    assert_equal @pub_priv_root.id, @pub_priv_fork4.parent&.id
    assert_equal @pub_priv_root.network.id, @pub_priv_fork4.network.id
    assert_equal "public", @pub_priv_fork4.visibility

    # fork5 is public but should get reparented to its public grandparent
    assert_equal @pub_priv_root.id, @pub_priv_fork5.parent&.id
    assert_equal @pub_priv_root.network.id, @pub_priv_fork5.network.id
    assert_equal "public", @pub_priv_fork5.visibility

    assert_same_elements [@pub_priv_fork4.id, @pub_priv_fork5.id], reparent_ids
  end

  test "delete public fork of private root parent" do
    network_id = @priv_pub_root.network.id

    o = RepositoryOrchestration.delete(@priv_pub_fork1, actor: User.ghost)

    reparent_ids = o.send(:fork_ids_to_reparent)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { o.execute }
    o.reload

    assert @priv_pub_root.reload.active?
    assert @priv_pub_fork1.reload.deleted?
    assert @priv_pub_fork2.reload.active?
    assert @priv_pub_fork3.reload.active?
    assert @priv_pub_fork4.reload.active?
    assert @priv_pub_fork5.reload.active?

    # the root is unchanged
    # public fork2 should be unchanged in the remaining mixed network
    assert_equal network_id, @priv_pub_fork2.network.id
    assert_equal @priv_pub_root.id, @priv_pub_fork2.network.root.id
    assert_equal "public", @priv_pub_fork2.visibility

    # private fork3 should be unchanged
    assert_equal network_id, @priv_pub_fork3.network.id
    assert_equal @priv_pub_root.id, @priv_pub_fork3.network.root.id
    assert_equal "private", @priv_pub_fork3.visibility

    # private fork4 should be reparented to its private grandparent
    assert_equal network_id, @priv_pub_fork4.network.id
    assert_equal @priv_pub_root.id, @priv_pub_fork4.parent&.id
    assert_equal @priv_pub_root.id, @priv_pub_fork4.network.root.id
    assert_equal "private", @priv_pub_fork4.visibility

    # private fork5 should be reparented to its private grandparent
    assert_equal network_id, @priv_pub_fork5.network.id
    assert_equal @priv_pub_root.id, @priv_pub_fork5.parent&.id
    assert_equal @priv_pub_root.id, @priv_pub_fork5.network.root.id
    assert_equal "private", @priv_pub_fork5.visibility

    assert_same_elements [@priv_pub_fork4.id, @priv_pub_fork5.id], reparent_ids
  end

  test "delete private fork of private root of mixed network" do
    network_id = @priv_priv_root.network.id
    assert_equal @priv_priv_fork1.id, @priv_priv_fork4.parent.id

    o = RepositoryOrchestration.delete(@priv_priv_fork1, actor: User.ghost)

    reparent_ids = o.send(:fork_ids_to_reparent)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { o.execute }
    o.reload

    assert @priv_priv_root.reload.active?
    assert @priv_priv_fork1.reload.deleted?
    assert @priv_priv_fork2.reload.active?
    assert @priv_priv_fork3.reload.active?
    assert @priv_priv_fork4.reload.active?
    assert @priv_priv_fork5.reload.active?

    # the private root should be unchanged
    # private fork2 should be reparented to the root
    assert       @priv_priv_fork2.network.id == network_id
    assert_equal @priv_priv_root.id, @priv_priv_fork2.network.root.id
    assert_equal "private", @priv_priv_fork2.visibility

    # private fork3 should be reparented to the root
    assert       @priv_priv_fork3.network.id == network_id
    assert_equal @priv_priv_root.id, @priv_priv_fork3.network.root.id
    assert_equal "private", @priv_priv_fork3.visibility

    # even though fork4 and fork5 are the wrong visibility (public)
    # just reparent them to their grandparent (private)
    assert_equal @priv_priv_root.network.id, @priv_priv_fork4.network.id
    assert_equal @priv_priv_root.id, @priv_priv_fork4.parent.id
    assert_equal "public", @priv_priv_fork4.visibility

    assert_equal @priv_priv_root.network.id, @priv_priv_fork5.network.id
    assert_equal @priv_priv_root.id, @priv_priv_fork5.parent.id
    assert_equal "public", @priv_priv_fork5.visibility

    assert_same_elements [@priv_priv_fork2.id, @priv_priv_fork3.id, @priv_priv_fork4.id, @priv_priv_fork5.id], reparent_ids
  end

  test "delete internal root" do
    network_id = @int_root.network.id
    o = delete_repo @int_root

    assert @int_root.reload.deleted?
    assert @int_fork1.reload.deleted?
    assert @int_fork2.reload.deleted?

    assert_equal network_id, @int_root.network.id
    assert_equal network_id, @int_fork1.network.id
    assert_equal network_id, @int_fork2.network.id

    assert_equal @int_root.id, @int_root.network.root.id
  end

  test "delete internal fork" do
    network_id = @int_root.network.id
    o = delete_repo @int_fork1

    assert @int_root.reload.active?
    assert @int_fork1.reload.deleted?
    assert @int_fork2.reload.active?

    assert_equal network_id, @int_root.network.id
    assert_equal network_id, @int_fork1.network.id
    assert_equal network_id, @int_fork2.network.id

    assert_equal @int_root.id, @int_root.network.root.id
  end

  test "skip if deleted" do
    # mark the repo as deleted
    @pub_root.update(active: nil)

    # the orchestration should be skipped because the repo is deleted
    o1 = RepositoryOrchestration.delete(@pub_root, actor: User.ghost)
    o1.execute

    assert_equal :skipped, o1.state.to_sym
    assert_equal :ensure_active, o1.step_name&.to_sym

    @pub_root.update(active: true)

    # start the first orchestration, should queue the job and be running
    o2 = RepositoryOrchestration.delete(@pub_root, actor: User.ghost)
    o2.execute
    assert_equal :running, o2.state.to_sym

    # finish the running orchestration
    o2.execute
    assert_equal :succeeded, o2.state.to_sym
    assert @pub_root.deleted?
  end

  test "nil deleter" do
    o1 = RepositoryOrchestration.delete(@pub_root, actor: nil)
    o1.execute(synchronous: true)
    assert_equal :succeeded, o1.state.to_sym
  end

  test "failed delete rolls back changes" do
    repo = create(:repository, from_example: :simple)
    repo.create_repository_auth_version(version: 42)

    # Mock a failure during the auth_version increment, after the version is updated in the DB
    repo.stubs(:reset_repository_auth_version).raises(StandardError.new("boom"))

    assert_predicate repo, :active?

    o = RepositoryOrchestration.delete(repo, actor: repo.owner)
    assert_raises StandardError do
      o.execute(synchronous: true)
    end

    assert_equal 1, o.attempts
    assert_equal "failed", o.state
    assert_equal "boom", o.error_message
    assert_equal "hide_repo", o.step_name

    repo.reload
    assert_predicate repo, :active?
    assert_equal 42, repo.auth_version
  end

  context "events" do
    test "deleting a fork from an org owned private repo does not change org_owned_private_networks_with_forks" do
      admin = create(:user)
      org = create(:organization, admin: admin)
      org.allow_private_repository_forking(actor: admin)
      other_org = create(:organization, admin: admin)
      other_org.allow_private_repository_forking(actor: admin)
      repo = create(:private_repository, owner: org)
      fork = create(:fork_repository, forker: admin, fork_repo: repo, organization: other_org)
      other_fork = create(:fork_repository, forker: admin, fork_repo: fork)

      assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

      # The root is still an OrgOwnedPrivateNetworkWithForks, so no change
      assert_difference("::OrgOwnedPrivateNetworkWithForks.count", 0) do
        delete_repo(fork)
      end

      assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
    end

    test "retrying HydroMessageJob tracks dogstats" do
      SecurityCenter::HydroRepositoryDeletedJob.any_instance.stubs(:perform).raises(ActiveRecord::RecordNotFound, "BOOM!").then.returns(1)

      user = create :user
      org = create :organization, admin: user
      repo = create(:repository, owner: org)

      perform_enqueued_hydro_jobs(only: [SecurityCenter::HydroRepositoryDeletedJob], allowed_primary_query_count: 2) do
        delete_repo(repo)
      end

      tags = [
        GitHub.enterprise? ? "catalog_service:github/unknown" : "catalog_service:github/security_center",
        "class:security_center/hydro_repository_deleted_job",
        "queue:hydro_security_center_repository_deleted",
        "topic:github.repositories.v1.Deleted"
      ]
      assert_dogstats_increment(1, "github.hydro_message_job.retried", tags:)
    end

    test "security center" do
      user = create :user
      org = create :organization, admin: user
      repo = create(:repository, owner: org)

      perform_enqueued_hydro_jobs(only: [SecurityCenter::HydroRepositoryDeletedJob], allowed_primary_query_count: 1) do
        delete_repo(repo)
      end

      assert_dogstats_distribution(1, "security_center.repository_updated.dist", tags: [
        "class:security_center/hydro_repository_deleted_job",
        "queue:hydro_security_center_repository_deleted",
        "topic:github.repositories.v1.Deleted",
      ])
    end

    test "delete packages" do
      Spokesd.enable_spokesd
      user = create :user
      org = create :organization, admin: user
      repo = create(:repository, owner: org)
      create(:registry_package, repository: repo)

      not_deleted_versions = repo.packages
        .map { |package| package.package_versions.not_deleted }
        .flatten

      refute_empty not_deleted_versions

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 16) do
        delete_repo(repo)
      end

      not_deleted_versions = repo.packages
        .map { |package| package.package_versions.not_deleted }
        .flatten

      assert_empty not_deleted_versions
    end

    test "update sponsors" do
      skip unless GitHub.sponsors_enabled?

      listing = create(:sponsors_listing)
      tier = create(:sponsors_tier, sponsors_listing: listing)
      repo = create(:repository, :full_creation, owner: listing.sponsorable)
      listing.featured_items.create(featureable: repo)

      assert_predicate listing.stafftools_metadata.reload, :has_public_non_fork_repository?

      assert_enqueued_jobs(2, only: [NullifyDependentRecordsJob, DeleteDependentRecordsJob]) do
        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 4) do
          delete_repo(repo)
        end
      end

      perform_enqueued_jobs(only: [NullifyDependentRecordsJob, DeleteDependentRecordsJob])

      refute_predicate listing.stafftools_metadata.reload, :has_public_non_fork_repository?
    end

    test "delete installations" do
      target = create(:credit_card_organization)
      admin  = target.admins.first
      repo = create(:repository, :minimal, owner: target)

      installation = make_integration_installation(target: target, repository: repo, permissions: { "metadata" => :read })

      perform_enqueued_hydro_jobs(only: [HydroDeleteInstallationsRepositoryDeletedJob], allowed_primary_query_count: 1) do
        delete_repo(repo)
      end

      perform_enqueued_jobs(only: [UninstallIntegrationInstallationJob]) do
        perform_enqueued_jobs(only: [IntegrationInstallationRepositoryRemovalJob])
      end

      assert_nil IntegrationInstallation.find_by(id: installation.id)
    end

    test "unpublish page" do
      repo = create(:repository)
      page = create(:page, repository: repo)
      refute_nil repo.reload.page

      perform_enqueued_hydro_jobs(only: [HydroUnpublishPageRepositoryDeletedJob], allowed_primary_query_count: 6) do
        delete_repo(repo)
      end

      assert_nil repo.reload.page
    end

    test "delete pull requests" do
      user1 = create(:user)
      forkable_repo = create(:repository, name: "test-repo", owner: user1, from_example: :pull_request_source)

      user2 = create(:user)
      forked_repo = create(:repository, name: "test-repo", owner: user2, from_example: :pull_request_source)

      pr = perform_enqueued_jobs(only: [UpdateRollupSummaryStateJob]) do
        create(:pull_request, repository: forkable_repo, base_repository: forkable_repo, head_repository: forked_repo, head_ref: "master-merged-topic")
      end

      PullRequest.any_instance.expects(:maintain_tracking_ref_with_retries).with(pr.safe_user)
      assert_equal "open", pr.issue.state

      # freeze time at the pr updated timestamp to prevent randomness in this check:
      # https://github.com/github/github/blob/b9a6b6d32ae8af497bad8df14d1932984ce20e76/packages/issues/app/models/issue.rb#L502
      # which can cause different numbers of queries depending on how fast the test reaches that code
      Timecop.freeze(pr.updated_at) do
        perform_enqueued_hydro_jobs(only: [HydroDeletePullRequestRepositoryDeletedJob], allowed_primary_query_count: 20) do
          delete_repo(forked_repo)
        end
      end

      assert_equal "closed", pr.issue.reload.state
    end

    test "generate hookshot payloads" do
      Spokesd.enable_spokesd
      user = create :user, :zuora, plan: "pro"
      repo = create :private_repository, owner: user
      other_repo_hook = create :hook, :web, installation_target: repo, events: %w(*)

      deliveries = subscribe_to_hook_delivery "repository"
      expected = GitHub.flipper[:repos_groups].enabled? ? 19 : 16
      perform_enqueued_jobs(only: [EnqueueToHookshotJob, RepositoryOrchestrationJob]) do
        perform_enqueued_hydro_jobs(only: [HydroGenerateHookshotPayloadsRepositoryDeletedJob], allowed_primary_query_count: expected) do
          repo.remove(user, synchronous: true)
        end
      end

      assert_equal 1, deliveries.count
    end

    test "disassociate parent repo advisory when deleting security workspace repo", skip_enterprise: true do
      advisory = create(:repository_advisory, :with_workspace)
      enable_feature_flag(:advisory_db_unrestorable_repositories, advisory.repository)
      repo = advisory.workspace_repository

      message = {
        actor_id: repo.owner.id,
        repository_id: advisory.workspace_repository.id,
        advisory_id: advisory.id,
      }

      assert_changes -> { advisory.reload.workspace_repository_id }, from: repo.id, to: nil do
        delete_repo(repo, actor: repo.owner)
      end

      with_hydro_publisher(GitHub.sync_hydro_publisher) do
        assert_hydro_published(message, schema: "github.repositories.v1.WorkspaceDeleted")
      end
    end

    test "publish fails, orchestration retries and ultimately fails" do
      repo = create(:repository)
      Hydro::Publisher.any_instance.stubs(:publish).returns(Hydro::Sink::Result.failure(Hydro::Sink::Error.new("RIP")))

      o = RepositoryOrchestration.delete(repo, actor: nil)
      perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) do
        o.execute(synchronous: false)
      end

      max_attempts = Orchestration::MAX_ATTEMPTS

      o.reload
      assert_equal "failed", o.state
      assert_equal "publish_deleted", o.step_name
      assert_equal max_attempts + 1, o.attempts

      assert_dogstats_increment max_attempts, "orchestration.hydro_publish.status", tags: ["success:false"]
    end

    test "increments the repository_auth_version", skip_enterprise: true do
      repo = create(:repository, from_example: :simple)
      repo.create_repository_auth_version(version: 42)

      # Freeze time so the hydro event timestamps match
      Timecop.freeze do
        RepositoryOrchestration.delete(repo, actor: repo.owner).execute(synchronous: true)
        repo.reload

        assert_equal 43, repo.auth_version

        assert_hydro_published({
          change: :DELETED,
          repository: Hydro::EntitySerializer.repository(repo),
          auth_version: 43,
        }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)

        assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
      end
    end
  end

  context "validate" do
    test "repository in never_delete list is not deleted" do
      GitHub.reset_never_delete_ids
      repo = create(:repository)
      GitHub.stubs(:never_delete).returns([repo.nwo])

      assert_equal [repo.id], GitHub.never_delete_ids

      delete_repo(repo)
      assert Repository.exists?(repo.id), "#{repo.nwo} should not have been deleted"
    end
  end

  context "while a visibility orchestration is running" do
    context "which triggers an extract orchestration of the fork" do
      context "then the owner of the root is deleted" do
        test "the delete orchestration should block until the visibility and extract orchestrations finish" do
          owner = create(:user)
          forker = create(:user)
          root = create(:private_repository, owner: owner, from_example: :simple)
          root.add_member(forker)
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { root.fork(forker: forker) }

          # Start changing visibility of the root, stop at the detach step.
          # This will trigger extracts of the forks, stop those at the create_new_network step
          visibility_orchestration = RepositoryOrchestration.set_visibility(root, actor: root.owner, visibility: Repository::PUBLIC_VISIBILITY)
          VisibilityRepositoryOrchestration.stop_after_step = :extract
          ExtractRepositoryOrchestration.stop_after_step = :create_new_network
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { visibility_orchestration.execute }

          # Delete the root owner. This will trigger a deletion orchestration for the root. We expect this orchestration
          # to block until the visibility and extract orchestrations finish
          VisibilityRepositoryOrchestration.stop_after_step = :toggle_permission
          owner.destroy!

          delete_orchestration = DeleteRepositoryOrchestration.find_by!(repository: root)
          assert_equal "waiting", delete_orchestration.state
          assert_equal "waiting", visibility_orchestration.reload.state
          extract_orchestration = ExtractRepositoryOrchestration.find_by!(parent: visibility_orchestration)
          assert_equal "running", extract_orchestration.state

          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { extract_orchestration.reload.execute }
          assert_equal "succeeded", extract_orchestration.reload.state
          assert_equal "running", visibility_orchestration.reload.state
          assert_equal "waiting", delete_orchestration.reload.state

          DeleteRepositoryOrchestration.stop_after_step = :elect_network_root
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { visibility_orchestration.reload.execute }
          assert_equal "succeeded", visibility_orchestration.reload.state
          assert_equal "running", delete_orchestration.reload.state

          perform_enqueued_jobs(only: RepositoryOrchestrationJob) { delete_orchestration.reload.execute }
          assert_equal "succeeded", delete_orchestration.reload.state

          assert_dogstats_increment(1, "repository_orchestration.blocked_on_concurrent", tags: ["type:VisibilityRepositoryOrchestration"])
        end
      end
    end
  end

  def delete_repo(repo, delete_forks_inaccessible_to: nil, actor: User.ghost)
    o = RepositoryOrchestration.delete(repo, actor: actor, delete_forks_inaccessible_to: delete_forks_inaccessible_to)

    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { o.execute }
    o.reload
  end
end
