# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRemovalDependencyTest < GitHub::TestCase
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include HydroMessageJobTestHelpers

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @org = create(:organization)
    @repo = create(:private_repository, owner: @org)
    @user = create(:credit_card_user)
    @org.add_member(@user, action: :admin)
    # Ensure members have admin access to repositories by default
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @org.update_default_repository_permission(:admin, actor: @org.admins.first)
    end
  end

  test "destroying a repo doesn't enable a user" do
    user = create :credit_card_user, plan: GitHub::Plan.pro
    repo = create :repository, owner: user
    priv_repo = create :private_repository, owner: user
    user.disable!

    repo.remove(user)
    priv_repo.remove(user)

    assert_predicate user.reload, :disabled?
  end

  test "purging a repo deletes its files on disk and deletes replicas and checksums" do
    repo = create :repository, owner: @user

    Repository.any_instance.expects(:remove_from_disk).once
    Repository.any_instance.expects(:remove_wiki_from_disk).once
    GitHub::DGit::Maintenance.expects(:delete_repo_replicas_and_checksums).once
    GitHub::DGit::Maintenance.expects(:delete_network_replicas).once

    repo.remove(@user, synchronous: true)
    repo.purge(synchronous: true)
  end

  test "purging a repo delete its pushes" do
    push = create(:push)
    push.repository.remove(@user, synchronous: true)

    assert_difference("Push.where(repository_id: #{push.repository_id}).count", -1) do
      perform_enqueued_jobs(only: [DeleteDependentRecordsJob]) { push.repository.purge(synchronous: true) }
    end

    refute Push.exists?(push.id)
  end

  test "purging a repo with integration_installations completes without error" do
    repo = create :repository, owner: @user
    integration = create(:integration, default_permissions: { "metadata" => :read })
    installation = make_integration_installation(integration: integration, repository: repo)

    Failbot.expects(:report!).never
    repo.remove(@user, synchronous: true)
    repo.purge(synchronous: true)
  end

  test "destroying a repo closes any PRs for which it is the head_repo" do
    @org.allow_private_repository_forking(actor: @user)
    fork_repo = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :simple)
    example_repo :simple, @repo

    pull = create(:pull_request,
      user: @user,
      repository: @repo,
      base_repository: @repo,
      head_repository: fork_repo,
      base_ref: "master",
      head_ref: "cr-line-endings"
    )
    perform_enqueued_hydro_jobs(only: [HydroDeletePullRequestRepositoryDeletedJob],
      allowed_primary_query_count: 38) do
      fork_repo.remove(@user, synchronous: true)
    end
    pull.reload
    assert_predicate pull, :closed?
    event = pull.issue.events.find_by(event: :closed, actor: @user)
    assert event
    assert_equal event.message, "head_repository_deleted"
  end

  test "destroying a repo ignores any orphaned PRs for which it is the head_repo" do
    @org.allow_private_repository_forking(actor: @user)
    fork_repo = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :simple)
    example_repo :simple, @repo

    pull = create(:pull_request,
      user: @user,
      repository: @repo,
      base_repository: @repo,
      head_repository: fork_repo,
      base_ref: "master",
      head_ref: "cr-line-endings"
    )
    # Delete the base_repository so that the PR is left orphaned
    @repo.delete

    fork_repo.remove(@user, synchronous: true)
    # The pull is ignored and so remains open
    pull.reload
    assert_predicate pull, :open?
  end

  test "destroying a private repo enables users on a per repo plan" do
    org = create :credit_card_org, plan: GitHub::Plan.diamond
    repo = create(:public_repository, owner: org)
    priv_repo = create :private_repository, owner: org
    org.disable!

    repo.remove(org, synchronous: true)
    assert_predicate org.reload, :disabled?

    priv_repo.remove(org, synchronous: true)
    refute_predicate org.reload, :disabled?
  end

  test "deleting a private repo deletes its child forks" do
    @org.allow_private_repository_forking(actor: @user)
    repo = create(:private_repository, owner: @org)
    fork, status = repo.fork(forker: @user)

    repo.remove(@user, synchronous: true)

    assert repo.reload.deleted?
    assert fork.reload.deleted?
  end

  test "deleting a public repo does not delete its child forks" do
    repo = create(:repository, owner: @org)
    fork, status = repo.fork(forker: @user)

    repo.remove(@user, synchronous: true)

    assert repo.reload.deleted?
    assert fork.reload.active?
  end

  test "user deleting their own private repo does not send email" do
    @org.allow_private_repository_forking(actor: @user)
    fork, status = @repo.fork(forker: @user)
    assert fork, "Fork should have succeeded but failed with status '#{status}'"

    RepositoryMailer.expects(:private_fork_deleted).never

    # Today it's not necessary to wait for jobs to test for this email, but this will
    # make the test more resilient in the event the email sending moves back into a job.
    fork.remove(@user, synchronous: true)

    assert Repositories::Public.is_deleted?(fork.id), "Private fork should be removed"
  end

  test "triggers a CodeQL database cleanup job upon repository deletion" do
    user = create(:user)
    repo = create(:public_repository, owner: user)

    assert_enqueued_jobs(1, only: CodeqlDatabaseCleanupJob) do
      repo.remove(@user, synchronous: true)
    end
  end

  test "enqueues a hydro message upon repository deletion", skip_enterprise: true do
    actor = create(:user)
    repo = create(:repository)
    repo.remove(actor, synchronous: true)

    repo_next_global_id = repo.global_relay_id
    unless GitHub.enterprise?
      repo_next_global_id = repo.next_global_id
    end

    assert_hydro_messages(count: 1, schema: "github.v1.RepositoryDeleted")

    assert_hydro_published({
      deleted_repository: Hydro::EntitySerializer.repository(repo, overrides: { next_global_id: repo_next_global_id }),
      actor: Hydro::EntitySerializer.user(actor),
    }, schema: "github.v1.RepositoryDeleted")
  end

  test "removing a repo recalculates its network counts" do
    repo = create(:public_repository, owner: @org)
    forked = create(:fork_repository, forker: @user, fork_repo: repo)
    forked2 = create(:fork_repository, forker: create(:user), fork_repo: forked)

    assert_equal repo.reload.public_fork_count, 2
    assert_equal forked.reload.public_fork_count, 1

    forked2.remove(@user, synchronous: true)

    assert_equal forked.reload.public_fork_count, 0
    assert_equal repo.reload.public_fork_count, 1

    forked.remove(@user, synchronous: true)

    assert_equal repo.reload.public_fork_count, 0
  end

  # A race condition seems to exist where the repo gets marked for deletion, then
  # some other action causes the repo to be marked as active and not deleted.
  # https://github.com/github/github/issues/150339
  context "Repo deletion race conditions protection" do
    test "racy calls to #remove do not raise errors" do
      user = actor = create(:user, plan: :pro)
      repo = create(:repository, owner: user)
      racy_instance = Repository.find(repo.id)

      repo.remove(user)

      # Pretend the first call hasn't finished yet, and second one starts.
      racy_instance.stubs(:active_changed?).returns(true)

      racy_instance.remove(user)
      assert_equal 0, racy_instance.errors.size
    end
  end

  test "repository deletion deletes associated package versions and files" do
    request_id = SecureRandom.uuid
    GitHub.context.push({ request_id: request_id })

    user = actor = create(:user, plan: :pro)
    repo = create(:repository, owner: user)

    # Deleting public package versions raises an error
    # by default so we assert here that we can do so.
    assert repo.public?

    package = repo.packages.new name: "test1", package_type: :docker
    version = package.package_versions.build version: "1.0", author: user
    version.files.build filename: "file", size: 1
    live_file = version.files.first

    version_deleted = package.package_versions.build version: "1.1", author: user
    version_deleted.files.build filename: "deleted-file", size: 1
    deleted_file = version_deleted.files.first

    package.save!

    # Pre-delete one of the versions to verify we see only
    # a Hydro event for the non-deleted version.
    version_deleted.delete!(force_delete: true)
    version_deleted.reload
    assert version_deleted.deleted?

    reset_hydro if GitHub.hydro_enabled?

    # Due to how records are deleted, associations need to be reloaded/assigned for this to match the event emitted.
    r = package.repository

    perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 13) do
      repo.remove(actor, synchronous: true)
    end

    package.reload
    package.repository = r
    version.reload
    version.package

    # the dependent records are not destroyed until the repo is removed from the repositories table
    repo.purge(synchronous: true)

    perform_enqueued_jobs(only: DestroyDependentRecordsJob)

    if GitHub.hydro_enabled? && !GitHub.flipper[:skip_package_destroy_in_repo_purge].enabled?
      assert_hydro_messages(count: 1, schema: "package_registry.v0.PackageVersionDeleted")
      assert_hydro_messages(count: 2, schema: "package_registry.v0.PackageFileDestroyed")

      message = {
        request_context: Hydro::EntitySerializer.request_context({ request_id: request_id }),
        actor: Hydro::EntitySerializer.user(actor),
        package: Hydro::EntitySerializer.package(package),
        version: Hydro::EntitySerializer.package_version(version, size: 1, files_count: 1),
        # deleted_at: Time.now.utc, Ignore deleted_at for now due to timestamp equality issue, even with Timecop
        storage_service: { name: "AWS_S3" },
        user_agent: nil,
        via_actions: false,
        event_id: request_id,
      }

      live_file_message = {
          artifact_id: live_file.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: repo.id },
      }

      deleted_file_message = {
          artifact_id: deleted_file.guid,
          storage_service: { name: "AWS_S3" },
          event_id: request_id,
          repository: { id: repo.id },
      }

      assert_hydro_published(message, schema: "package_registry.v0.PackageVersionDeleted", ignore_extra_keys: true)
      assert_hydro_published(live_file_message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)
      assert_hydro_published(deleted_file_message, schema: "package_registry.v0.PackageFileDestroyed", ignore_extra_keys: true)
    end
  end

  context "Deletion of repos in bad states" do
    test "we can delete a repo when it has lost its network" do
      user = create(:user, plan: :pro)
      repo = create(:repository, owner: user)
      repo.network.delete
      repo.remove(user, synchronous: true)

      assert Repositories::Public.is_deleted?(repo.id)

      repo.purge(synchronous: true)

      assert_raises(ActiveRecord::RecordNotFound) { Repository.find(repo.id) }
    end

    test "we can delete and purge a repo which has no network replicas" do
      user = create(:user, plan: :pro)
      repo = create(:repository, owner: user)

      GitHub::DGit::Maintenance.delete_network_replicas(repo.network.id)
      db = GitHub::DGit::DB.for_network_id(repo.network.id)
      db = GitHub::DGit::DB.for_network_id(repo.network.id)
      network_replicas = db.SQL.new(network_id: repo.network.id).run <<-SQL
        SELECT COUNT(*)
          FROM network_replicas
          WHERE network_id=:network_id
      SQL
      assert_equal 0, network_replicas.values.first

      repo_replicas = db.SQL.new(network_id: repo.network.id, repo_id: repo.id).run <<-SQL
        SELECT COUNT(*)
          FROM repository_replicas
          WHERE repository_id=:repo_id
      SQL
      assert_equal 3, repo_replicas.values.first

      repo.remove(user, synchronous: true)
      assert Repositories::Public.is_deleted?(repo.id)

      repo.purge(synchronous: true)
      assert_raises(ActiveRecord::RecordNotFound) { Repository.find(repo.id) }

      network_replicas = db.SQL.new(network_id: repo.network.id).run <<-SQL
        SELECT COUNT(*)
          FROM network_replicas
          WHERE network_id=:network_id
      SQL
      assert_equal 0, network_replicas.values.first

      repo_replicas = db.SQL.new(network_id: repo.network.id, repo_id: repo.id).run <<-SQL
        SELECT COUNT(*)
          FROM repository_replicas
          WHERE repository_id=:repo_id
      SQL
      assert_equal 0, repo_replicas.values.first
    end

    test "we can delete and purge a repo which has no repo replicas" do
      user = create(:user, plan: :pro)
      repo = create(:repository, owner: user)

      GitHub::DGit::Maintenance.delete_repo_replicas_and_checksums(repo.network.id, repo.id)
      db = GitHub::DGit::DB.for_network_id(repo.network.id)
      network_replicas = db.SQL.new(network_id: repo.network.id).run <<-SQL
        SELECT COUNT(*)
          FROM network_replicas
          WHERE network_id=:network_id
      SQL
      assert_equal 3, network_replicas.values.first

      repo_replicas = db.SQL.new(network_id: repo.network.id, repo_id: repo.id).run <<-SQL
        SELECT COUNT(*)
          FROM repository_replicas
          WHERE repository_id=:repo_id
      SQL
      assert_equal 0, repo_replicas.values.first

      repo.remove(user, synchronous: true)
      assert Repositories::Public.is_deleted?(repo.id)

      repo.purge(synchronous: true)
      assert_raises(ActiveRecord::RecordNotFound) { Repository.find(repo.id) }

      network_replicas = db.SQL.new(network_id: repo.network.id).run <<-SQL
        SELECT COUNT(*)
          FROM network_replicas
          WHERE network_id=:network_id
      SQL
      assert_equal 0, network_replicas.values.first

      repo_replicas = db.SQL.new(network_id: repo.network.id, repo_id: repo.id).run <<-SQL
        SELECT COUNT(*)
          FROM repository_replicas
          WHERE repository_id=:repo_id
      SQL
      assert_equal 0, repo_replicas.values.first
    end
  end

  context "cannot_delete_or_transfer_repository_reason" do
    test "returns :cant_administer if not adminable by user" do
      user = create(:user)
      assert_equal :cant_administer, @repo.cannot_delete_or_transfer_repository_reason(user)
    end

    test "returns nil if user is a site admin and unlocked repo by" do
      site_admin = create(:staff_admin_user)

      assert_equal :cant_administer, @repo.cannot_delete_or_transfer_repository_reason(site_admin)

      admin_unlock_repo(site_admin, @repo)

      assert_nil @repo.cannot_delete_or_transfer_repository_reason(site_admin)
    end

    test "returns nil if owner is a user" do
      user_repo = create(:repository, owner: @user)
      assert_nil user_repo.cannot_delete_or_transfer_repository_reason(@user)
    end

    test "returns nil if owner is a default org and appliance is default" do
      assert_nil @repo.cannot_delete_or_transfer_repository_reason(@user)
    end

    test "returns nil if members_can_delete_repositories is disabled and appliance is default" do
      @org.disallow_members_can_delete_repositories(actor: @user)
      assert_nil @repo.cannot_delete_or_transfer_repository_reason(@user)
    end

    test "returns :members_cant_delete_repositories for non-admin if members_can_delete_repositories is disabled and appliance is default" do
      @org.disallow_members_can_delete_repositories(actor: @user)
      user = create(:user)
      @repo.add_member(user, action: :admin)
      assert_equal :members_cant_delete_repositories, @repo.cannot_delete_or_transfer_repository_reason(user)
    end

    test "returns :ofac_trade_restricted for private repos of users that have been trade restricted" do
      user = create(:user)
      repo = create(:private_repository, owner: user)
      user.trade_controls_restriction.full!

      assert_equal :ofac_trade_restricted, repo.cannot_delete_or_transfer_repository_reason(user)
    end

    test "public repo can be deleted by partially trade restricted org" do
      organization = create(:organization)
      repo = create(:repository, owner: organization)
      organization.trade_controls_restriction.partial!

      refute repo.cannot_delete_or_transfer_repository_reason(organization.admin)
    end

    test "returns :ofac_trade_restricted for public repos owned by organizations that have been fully trade restricted" do
      organization = create(:organization)
      repo = create(:repository, owner: organization)
      organization.trade_controls_restriction.full!

      assert_equal :ofac_trade_restricted, repo.cannot_delete_or_transfer_repository_reason(organization.admin)
    end

    test "public repo can be deleted by tier_0 trade restricted org" do
      organization = create(:organization)

      repo = create(:repository, owner: organization)
      organization.trade_controls_restriction.tier_0!

      refute repo.cannot_delete_or_transfer_repository_reason(organization.admin)
    end

    test "returns nil for public repositories of trade restricted users" do
      user = create(:user, :fully_trade_restricted)
      repo = create(:repository, owner: user)
      user.trade_controls_restriction.full!

      assert_nil repo.cannot_delete_or_transfer_repository_reason(user)
    end

    test "returns :not_ready_for_writes if repo is not ready for writes" do
      user = create :user
      repo = create :repository, owner: user
      # When a repo and its replicas are created in network, their checksums are initially
      # set to `creating`, which signals that the repo is not able to accept writes.
      # Here, we can mimick that initial "unready" state by updating the checksums.
      hosts = GitHub::DGit::Routing.hosts_for_repo(repo.id)
      repo_checksum = "creating"
      replica_checksums = Hash[hosts.map { |h| [h, repo_checksum] }]
      GitHub::DGit::Delegate.update_checksums(repo.network_id, repo.id, false, replica_checksums, repo_checksum)

      assert_predicate repo, :creating?
      refute_predicate repo, :ready_for_writes?
      Timecop.travel(repo.created_at + 1.minute) do
        assert_equal :not_ready_for_writes, repo.cannot_delete_or_transfer_repository_reason(user)
      end
    end

    test "returns nil if repo is not ready for writes but was created beyond the threshold" do
      user = create :user
      repo = Timecop.travel(2 * Repository::RemovalDependency::PREVENT_DELETION_THRESHOLD) do
        create :repository, owner: user
      end
      # When a repo and its replicas are created in network, their checksums are initially
      # set to `creating`, which signals that the repo is not able to accept writes.
      # Here, we can mimick that initial "unready" state by updating the checksums.
      hosts = GitHub::DGit::Routing.hosts_for_repo(repo.id)
      repo_checksum = "creating"
      replica_checksums = Hash[hosts.map { |h| [h, repo_checksum] }]
      GitHub::DGit::Delegate.update_checksums(repo.network_id, repo.id, false, replica_checksums, repo_checksum)

      assert_predicate repo, :creating?
      refute_predicate repo, :ready_for_writes?
      assert_nil repo.cannot_delete_or_transfer_repository_reason(user)
    end

    test "returns :members_cant_delete_repositories for non-org-admin if members_can_delete_repositories even if site admin", skip_enterprise: true do
      @org.disallow_members_can_delete_repositories(actor: @user)
      site_admin = create :staff_admin_user
      @repo.add_member(site_admin, action: :admin)
      assert_equal :members_cant_delete_repositories, @repo.cannot_delete_or_transfer_repository_reason(site_admin)
    end


    if GitHub.enterprise?
      # "Repository deletion and transfer" global business setting description:
      #
      # If enabled, members with admin permissions for the repository will be
      # able to delete or transfer public and private repositories. If disabled,
      # only organization owners can delete or transfer repositories.

      test "returns nil for org admin if owner is org and disallow_members_can_delete_repositories is enabled" do
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @user)
        assert_nil @repo.cannot_delete_or_transfer_repository_reason(@user)
      end

      test "returns :cant_delete_repos_on_this_appliance for non-org admin if owner is org and disallow_members_can_delete_repositories is enabled" do
        non_org_admin = create :user
        @org.add_member(non_org_admin)
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @user)
        assert_equal :cant_delete_repos_on_this_appliance, @repo.cannot_delete_or_transfer_repository_reason(non_org_admin)
      end

      test "returns nil for site admins" do
        site_admin = create :staff_admin_user
        GitHub.global_business.disallow_members_can_delete_repositories(force: true, actor: @user)
        @repo.add_member(site_admin, action: :admin)
        assert_nil @repo.cannot_delete_or_transfer_repository_reason(site_admin)
      end
    end
  end

  context "Deleting checks and actions related data" do
    test "remove non-actions checks suites and related dependencies" do
      repo = create(:repository, owner: @user)
      check_suite = create(:check_suite, repository: repo)
      check_run = create(:check_run, check_suite: check_suite)
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.remove(@user, synchronous: true) }

      assert_nil CheckSuite.find_by(id: check_suite.id)
      assert_nil CheckRun.find_by(id: check_run.id)
    end

    test "remove actions checks suites, workflow runs and related dependencies" do
      GitHub.stubs(:actions_enabled?).returns(true)
      make_trusted_oauth_apps_owner

      repo = create(:repository, owner: @user)
      check_suite = create(:check_suite_for_actions_app, repository: repo)
      check_run = create(:check_run_for_actions_app, check_suite: check_suite)
      workflow_run = check_suite.workflow_run
      workflow_job_run = check_run.workflow_job_run

      CheckSuite.any_instance.stubs(:delete_logs_from_file_storage).returns(nil)
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { repo.remove(@user, synchronous: true) }

      assert_nil CheckSuite.find_by(id: check_suite.id)
      assert_nil CheckRun.find_by(id: check_run.id)
      assert_nil Actions::WorkflowRun.find_by(id: workflow_run.id)
      assert_nil Actions::WorkflowJobRun.find_by(id: workflow_job_run.id)
    end

    test "removes a repository_action" do
      repo = create(:repository, owner: @user)
      action = create(:repository_action, path: "action.yml", repository: repo)

      repo.remove(@user, synchronous: true)

      assert_difference("RepositoryAction.count", -1) do
        repo.purge(synchronous: true)
      end
    end

    test "removes a repository_action when owner no longer exists" do
      repo = create(:repository)
      action = create(:repository_action, path: "action.yml", repository: repo)

      repo.remove(@user, synchronous: true)
      repo.owner.destroy
      repo.reload

      assert_difference("RepositoryAction.count", -1) do
        repo.purge(synchronous: true)
      end
    end
  end

  context "Delete media blobs" do
    test "removing the last repo in a network deletes media blobs" do
      create :billing_platform_enabled_product, customer: @user.customer, git_lfs: true

      repo = create :repository, owner: @user
      file1 = create :asset, size: 500.megabytes
      create(:media_blob, asset: file1, repository_network: repo.network, state: 3)

      RepositoryNetwork.any_instance.expects(:delete_media_blobs).times(1)
      Billing::Platform::Api::Client.any_instance.stubs(:get_watermark_level).returns({ quantity: 50 })

      Timecop.freeze(DateTime.parse("2023-02-01 04:05:06 UTC")) do
        repo.remove(@user, synchronous: true)

        unless GitHub.enterprise?
          assert_equal 1, hydro_message_count(schema: "billingplatform.v1.Usage")
          assert_hydro_published({
              sku: "git_lfs_storage",
              quantity: -50.0,
              usage_at: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i),
              source_uri: "gid://git-hub/reset/#{repo.id}",
              entity: { customer_id: @user.customer.id, organization_id: 0, repo_id: repo.id, actor_id: @user.id }
            },
            schema: "billingplatform.v1.Usage",
            count: 1
          )
        end
      end
    end

    test "removing a repo from a network with other repos does not delete media blobs" do
      repo = create(:public_repository, owner: @org)
      forked = create(:fork_repository, forker: @user, fork_repo: repo)

      RepositoryNetwork.any_instance.expects(:delete_media_blobs).times(0)
      forked.remove(@user, synchronous: true)
    end
  end

  if GitHub.sponsors_enabled?
    # https://github.com/github/sponsors/issues/3327
    context "Sponsors listing metadata" do
      test "updates has_public_non_fork_repository to false when the maintainer's last public non-fork repository is deleted" do
        sponsorable = create(:user)
        repo = create(:repository, owner: sponsorable)
        listing = create(:sponsors_listing, sponsorable: sponsorable)

        metadata = listing.stafftools_metadata

        assert_predicate metadata, :has_public_non_fork_repository?
        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 4) do
          repo.remove(sponsorable, synchronous: true)
        end
        refute_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "updates has_public_non_fork_repository to false when the maintainer only has a private non-fork repo and a public fork repo left" do
        sponsorable = create(:user)
        private_repo = create(:private_repository, owner: sponsorable)
        source_repo = create(:repository)
        public_forked_repo = create(:fork_repository, forker: sponsorable, fork_repo: source_repo)
        public_repo = create(:repository, owner: sponsorable)

        listing = create(:sponsors_listing, sponsorable: sponsorable)

        metadata = listing.stafftools_metadata

        assert_predicate metadata, :has_public_non_fork_repository?
        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 4) do
          public_repo.remove(sponsorable, synchronous: true)
        end
        refute_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does not update Sponsors listing metadata when has_public_non_fork_repository is already false" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        sponsorable = create(:user)
        repo = create(:private_repository, owner: sponsorable)
        listing = create(:sponsors_listing, sponsorable: sponsorable)

        metadata = listing.stafftools_metadata

        refute_predicate metadata, :has_public_non_fork_repository?
        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 2) do
          repo.remove(sponsorable, synchronous: true)
        end
        refute_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does not update Sponsors listing metadata when the repo owner has another public non-fork repo" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        sponsorable = create(:user)
        removable_repo = create(:repository, owner: sponsorable)
        public_non_fork_repo_to_keep = create(:repository, owner: sponsorable)
        listing = create(:sponsors_listing, sponsorable: sponsorable)

        metadata = listing.stafftools_metadata

        assert_predicate metadata, :has_public_non_fork_repository?
        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 4) do
          removable_repo.remove(sponsorable, synchronous: true)
        end
        assert_predicate metadata.reload, :has_public_non_fork_repository?
      end

      test "does nothing if repo owner does not have a Sponsors listing" do
        SponsorsListingStafftoolsMetadata.any_instance.expects(:update_column).never

        owner = create(:user)
        repo = create(:repository, owner: owner)

        perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 2) do
          repo.remove(owner, synchronous: true)
        end
      end
    end

    context "Sponsors tiers" do
      test "nullifies sponsors_tiers when repo is removed" do
        tier = create(:sponsors_tier, :with_repository)
        repo = tier.repository

        perform_enqueued_jobs(only: [NullifyDependentRecordsJob]) do
          perform_enqueued_hydro_jobs(only: [HydroSponsorsRepositoryDeletedJob], allowed_primary_query_count: 2) do
            repo.remove(repo.owner, synchronous: true)
          end
        end

        assert_nil tier.reload.repository
      end
    end
  end
end
