# typed: false
# frozen_string_literal: true

require "test_helper"

class PurgeRepositoryOrchestrationTest < GitHub::TestCase
  include DogstatsTestHelpers
  include HydroTestHelpers
  include HydroMessageJobTestHelpers
  include CustomPropertiesTestHelper

  fixtures do
    @repo = create(:repository)
  end

  test "should fail on invalid repository" do
    o = RepositoryOrchestration.purge(@repo)
    o.execute
    assert o.failed?
  end

  test "should fail if deleted and a legal hold is present" do
    delete_repo(@repo)

    user = @repo.owner
    user.place_legal_hold(actor: @staff)
    assert_predicate user, :legal_hold?

    o = RepositoryOrchestration.purge(@repo)
    o.execute
    assert o.failed?
  end

  test "should perform if soft-deleted" do
    GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(@repo.repository_spec).returns(:ok)
    GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(@repo.unsullied_wiki.repository_spec).returns(:ok)

    delete_repo(@repo)

    o = purge_repo(@repo)

    assert_nil Repository.find_by_id(o.repository_id)
    assert o.succeeded?
  end

  test "skip duplicated orchestration" do
    GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(@repo.repository_spec).returns(:ok)
    GitHub::Gitbackups::Client.any_instance.stubs(:delete).with(@repo.unsullied_wiki.repository_spec).returns(:ok)

    delete_repo(@repo)

    o1 = RepositoryOrchestration.purge(@repo)
    o1.save!
    o2 = RepositoryOrchestration.purge(@repo)
    o2.save!(validate: false)
    o2.errors.clear

    # simulating synchronous phase in parallel
    o1.execute!
    o2.execute!

    # simulating asynchronous phase
    o1.execute!
    o1.reload

    assert_nil Repository.find_by_id(o1.repository_id)
    assert o1.succeeded?

    assert o2.skipped?
  end

  test "should publish Purged event" do
    delete_repo(@repo)

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      o = purge_repo(@repo)

      assert_nil Repository.find_by_id(o.repository_id)

      assert_hydro_messages(count: 1, schema: "github.repositories.v1.Purged")
      assert_hydro_published({ repository_id: o.repository_id }, schema: "github.repositories.v1.Purged")
    end
  end

  test "should deletes repo files on disk and deletes replicas and checksums" do
    delete_repo(@repo)

    Repository.any_instance.expects(:remove_from_disk).once
    Repository.any_instance.expects(:remove_wiki_from_disk).once
    GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).once
    GitHub::DGit::Maintenance.expects(:delete_network_replicas).once

    o = purge_repo(@repo)

    assert_nil Repository.find_by_id(o.repository_id)
  end

  test "should delete its pushes" do
    repo = create(:repository)
    push = create(:push, repository: repo)

    delete_repo repo

    assert_difference("Push.where(repository_id: #{push.repository_id}).count", -1) do
      purge_repo(repo, perform_jobs: [DeleteDependentRecordsJob])
    end

    refute Push.exists?(push.id)
  end

  test "should delete its custom properties" do
    org = create(:organization)
    repo = create(:repository, owner: org)

    definition = create :custom_property_definition, source: org, property_name: "environment"
    create :custom_property_value, definition: definition, target: repo, value: "value"
    assert_equal repo_properties(repo, :manual), { "environment" => "value" }

    delete_repo repo

    assert_difference("CustomPropertyValue.for_target(repo).count", -1) do
      purge_repo(repo)
    end

    assert_empty CustomPropertyValue.for_target(repo)
  end

  test "should perform even if repo is in a bad state" do
    @repo.network.delete

    delete_repo(@repo)

    o = purge_repo(@repo)

    assert_nil Repository.find_by_id(o.repository_id)
  end

  test "when repository soft-creation fails, we can successfully purge the repo" do
    @user = create(:user)
    RepositoryNetwork.any_instance.stubs(:initialize_placeholder_network_replicas).raises(StandardError)
    result = create_repository(owner: @user.to_s, public: false)
    repo = result.repository.reload

    refute result.success
    assert_nil repo.active
    assert_nil repo.deleted_at

    o = purge_repo(repo)
    assert_nil Repository.find_by_id(o.repository_id)
  end

  test "skip if repo is already purged" do
    delete_repo(@repo)
    o = RepositoryOrchestration.purge(@repo)
    @repo.destroy
    o.execute
    assert_equal :skipped, o.state.to_sym
    assert_equal "already purged", o.error_message
  end

  test "should fail if repo cannot be removed from disk" do
    repo = create(:repository)
    delete_repo repo
    Repository.any_instance.stubs(:remove_from_disk).raises(GitHub::Spokes::ClientError)

    orchestration = purge_repo(repo)

    assert_equal :failed, orchestration.state.to_sym
    max_attempts = Orchestration::MAX_ATTEMPTS
    assert_equal max_attempts + 1, orchestration.attempts
  end

  context "when repository is destroyed" do
    test "should be able to re-run successfully" do
      delete_repo(@repo)

      o = RepositoryOrchestration.purge(@repo)

      DeleteDependentRecordsJob.expects(:perform_later).raises(StandardError, "boom")

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        assert_raises(StandardError, "boom") do
          o.execute
        end
      end

      o.reload

      assert_nil Repository.find_by_id(o.repository_id)
      refute o.succeeded?

      DeleteDependentRecordsJob.unstub(:perform_later)

      o = perform_orchestration(o)
      assert o.succeeded?

    end
  end

  test "hydro publish fails, orchestration retries and ultimately succeeds" do
    delete_repo(@repo)

    GitHub.sync_hydro_publisher
      .stubs(:publish)
      .returns(Hydro::Sink::Result.failure(Hydro::Sink::Error.new("RIP")))
      .then.returns(Hydro::Sink::Result.success)

    o = RepositoryOrchestration.purge(@repo)

    with_hydro_publisher(GitHub.sync_hydro_publisher) do
      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        o.execute
      end
    end

    o.reload
    assert o.succeeded?
  end

  test "repository deletion deletes associated package versions and files" do
    GitHub.flipper[:skip_package_destroy_in_repo_purge].disable

    assert_difference "Registry::Package.count", 3 do
      assert_difference "Registry::PackageVersion.count", 3 do
        assert_difference "Registry::File.count", 3 do
          3.times { create(:registry_package, repository: @repo) }
        end
      end
    end

    delete_repo(@repo)
    o = RepositoryOrchestration.purge(@repo)

    assert_difference "Registry::Package.count", -3 do
      assert_difference "Registry::PackageVersion.count", -3 do
        assert_difference "Registry::File.count", -3 do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
            o.execute
          end
        end
      end
    end

    assert o.reload.succeeded?
  end

  test "repository purge leaves packages in place to be cleaned up by DestroyDeletedPackageVersionsJob" do
    GitHub.flipper[:skip_package_destroy_in_repo_purge].enable
    GitHub.flipper[:packages_disable_destroy_delete_package_versions_job].disable

    Timecop.freeze(4.months.ago) do
      assert_difference "Registry::Package.count", 3 do
        assert_difference "Registry::PackageVersion.count", 3 do
          assert_difference "Registry::File.count", 3 do
            3.times { create(:registry_package, repository: @repo) }
          end
        end
      end

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob]) do
        delete_repo(@repo)
      end
    end

    o = RepositoryOrchestration.purge(@repo)

    assert_difference "Registry::Package.count", 0 do
      assert_difference "Registry::PackageVersion.count", 0 do
        assert_difference "Registry::File.count", 0 do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
            o.execute
          end
        end
      end
    end

    assert o.reload.succeeded?

    assert_difference "Registry::Package.count", -3 do
      assert_difference "Registry::PackageVersion.count", -3 do
        assert_difference "Registry::File.count", -3 do
          DestroyDeletedPackageVersionsJob.perform_now
        end
      end
    end
  end

  test "repository deletion deletes associated package versions and files attempts" do
    GitHub.flipper[:skip_package_destroy_in_repo_purge].disable

    assert_difference "Registry::Package.count", 3 do
      assert_difference "Registry::PackageVersion.count", 3 do
        assert_difference "Registry::File.count", 3 do
          3.times { create(:registry_package, repository: @repo) }
        end
      end
    end

    delete_repo(@repo)
    o = RepositoryOrchestration.purge(@repo)

    Registry::PackageVersion.any_instance.stubs(:destroy).raises(Freno::Throttler::Error)

    assert_difference "Registry::Package.count", 0 do
      assert_difference "Registry::PackageVersion.count", 0 do
        assert_difference "Registry::File.count", 0 do
          perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
            o.execute
          end
        end
      end
    end

    assert o.reload.succeeded?
  end


  test "purging an org owned private networks only fork syncs org_owned_private_networks_with_forks" do
    GitHub.flipper[:sync_org_owned_private_network_with_forks].enable

    admin = create(:user)
    org = create(:organization, admin: admin)
    org.allow_private_repository_forking(actor: admin)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: admin, fork_repo: repo)

    assert OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?

    delete_repo(fork)
    assert_difference("::OrgOwnedPrivateNetworkWithForks.count", -1) do
      purge_repo(fork)
    end

    refute OrgOwnedPrivateNetworkWithForks.where(network_id: repo.network_id, owner_id: repo.owner_id).exists?
  end

  def purge_repo(repo, perform_jobs: [])
    o = RepositoryOrchestration.purge(repo)
    perform_orchestration(o, perform_jobs:)
  end

  def perform_orchestration(orchestration, perform_jobs: [])
    jobs = ([RepositoryOrchestrationJob] + perform_jobs).uniq
    perform_enqueued_jobs(only: jobs) do
      orchestration.execute
    end
    orchestration.reload
  end

  def delete_repo(repo)
    o = RepositoryOrchestration.delete(repo, actor: repo.owner)
    perform_enqueued_jobs(only: RepositoryOrchestrationJob) { o.execute }
    o.reload
  end

  def create_repository(params = {}, repo_class = Repository)
    repo_params = {
      name: "reponame",
      description: "an description",
      public: true,
      user: @user,
    }.merge(params)
    owner = repo_params.delete(:owner)
    billing = repo_params.delete(:billing)
    user = repo_params.delete(:user)

    repo_class.handle_creation(
      user,
      owner,
      repo_params,
      reflog_data = {},
      billing,
    )
  end
end
