# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodeqlDatabaseCleanupJobTest < GitHub::TestCase
  include UploadableTestHelpers

  fixtures do
    @user = create(:user)

    @public_user_repo = create(:public_repository, owner: @user)
    @public_bulk_builder_repo = create(:public_repository, owner: @user)
    @private_user_repo = create(:private_repository, owner: @user)
    @private_bulk_builder_repo = create(:private_repository, owner: @user)
    @inactive_repo = create(:public_repository, owner: @user, active: false)
    @deleted_repo = create(:public_repository, owner: @user) # Will be deleted in setup block

    make_trusted_oauth_apps_owner
    @code_scanning_app = create :code_scanning_integration

    # For each repository create a variety of databases and record them all
    # so that in the tests we can assert exactly which databases are deleted.
    @all_repos = @user.repositories + [@inactive_repo]
    @old_dbs = @all_repos.flat_map { |repo| generate_old_databases(repo) }.freeze
    @old_invalid_dbs = @all_repos.flat_map { |repo| generate_old_invalid_databases(repo) }.freeze
    @new_starter_dbs = @all_repos.map { |repo| generate_new_starter_database(repo) }.freeze
    @active_dbs = @all_repos.flat_map { |repo| generate_active_databases(repo) }.freeze
    @uploadable = create(:codeql_database)
  end

  # User that should be used when creating CodeQL databases for the given test repo.
  def uploader_for_repo(repo)
    return @code_scanning_app.bot if [@public_bulk_builder_repo.id, @private_bulk_builder_repo.id].include? repo.id
    @user
  end

  # Creates two old databases that are now superseded by the active databases.
  # Both of these can be cleaned up.
  # Returns the databases that were created.
  def generate_old_databases(repo)
    [
      Timecop.freeze(3.days.ago) { create(:codeql_database, repository: repo, uploader: uploader_for_repo(repo)) },
      Timecop.freeze(4.days.ago) { create(:codeql_database, repository: repo, uploader: uploader_for_repo(repo)) },
    ]
  end

  # Creates two old databases in non-uploaded states.
  # These can always been cleaned up once they reach a certain age.
  # Returns the databases that were created.
  def generate_old_invalid_databases(repo)
    Timecop.freeze(2.weeks.ago) do
      [
        create(:codeql_database, repository: repo, state: :starter, uploader: uploader_for_repo(repo)),
        create(:codeql_database, repository: repo, state: :deleted, uploader: uploader_for_repo(repo)),
      ]
    end
  end

  # Creates one recent database in the process of being uploaded.
  # Should not ever be deleted, even for a deleted repository, until it reaches a certain age.
  # Returns the database that was created.
  def generate_new_starter_database(repo)
    create(:codeql_database, repository: repo, state: :starter, uploader: uploader_for_repo(repo))
  end

  # Creates three valid active databases for this repo.
  # All of these databases are considered active because they could have signed URLs that are still valid.
  # Needs to be created last becase code assumed that IDs and created_at timestamps are the same ordering.
  # Should only be cleaned up if the repository is deleted.
  def generate_active_databases(repo)
    [
      Timecop.freeze(2.days.ago) { create(:codeql_database, repository: repo, uploader: uploader_for_repo(repo)) },
      Timecop.freeze(1.hour.ago) { create(:codeql_database, repository: repo, uploader: uploader_for_repo(repo)) },
      create(:codeql_database, repository: repo, uploader: uploader_for_repo(repo)),
    ]
  end

  def setup
    @deleted_repo.delete
  end

  # Asserts that for the given repo, the only CodeQL databases that exist coem from the set given.
  # The expected_dbs is an array of CodeqlDatabase objects but may include databases for other
  # repositories. This array will be filtered to only include databases for the intended repo
  # before comparing with the set of existing databases.
  def assert_only_these_databases_exist(repo_id, expected_dbs)
    expected_dbs = expected_dbs.filter { |db| db.repository_id == repo_id }.to_set
    all_existing_dbs = CodeqlDatabase.where(repository_id: repo_id).to_set
    assert_equal expected_dbs, all_existing_dbs
  end

  context "dotcom only", skip_enterprise: true do
    test "for public user repo deletes all dbs except active and new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)
      assert_only_these_databases_exist(@public_user_repo.id, @new_starter_dbs + @active_dbs)
    end

    test "for public bulk builder repo deletes all dbs except active and new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_bulk_builder_repo.id)
      assert_only_these_databases_exist(@public_bulk_builder_repo.id, @new_starter_dbs + @active_dbs)
    end

    test "for private user repo deletes all dbs except active and new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @private_user_repo.id)
      assert_only_these_databases_exist(@private_user_repo.id, @new_starter_dbs + @active_dbs)
    end

    test "for private bulk builder repo deletes all dbs except new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @private_bulk_builder_repo.id)
      assert_only_these_databases_exist(@private_bulk_builder_repo.id, @new_starter_dbs)
    end

    test "for inactive repo deletes all dbs except new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @inactive_repo.id)
      assert_only_these_databases_exist(@inactive_repo.id, @new_starter_dbs)
    end

    test "for deleted repo deletes all dbs except new starter db" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @deleted_repo.id)
      assert_only_these_databases_exist(@deleted_repo.id, @new_starter_dbs)
    end

    test "increments dogstats" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)
      assert_equal 4, GitHub.dogstats.increments("code_scanning.codeql_database.deleted").count
    end

    test "calls the storage_delete_object callback" do
      CodeqlDatabase.any_instance.expects(:storage_delete_object_if_exists).times(4)
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)
    end

    test "doesn't touch databases for other repos" do
      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)

      @all_repos.each do |repo|
        if repo.id == @public_user_repo.id
          assert_only_these_databases_exist(repo.id, @new_starter_dbs + @active_dbs)
        else
          assert_only_these_databases_exist(repo.id, @old_dbs + @old_invalid_dbs + @new_starter_dbs + @active_dbs)
        end
      end
    end

    test "doesn't run if lock is taken" do
      GitHub::Restraint.new.lock!("#{CodeqlDatabaseCleanupJob.name}:#{@public_user_repo.id}", 1, 1.minute) do
        CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)
      end

      assert_equal 8, CodeqlDatabase.where(repository: @public_user_repo).count
    end

    test "handles when there are clashing created_at timestamps" do
      CodeqlDatabase.delete_all

      superseded_database = T.let(nil, T.nilable(CodeqlDatabase))
      latest_database = T.let(nil, T.nilable(CodeqlDatabase))
      Timecop.freeze(1.day.ago) do
        superseded_database = create(:codeql_database, repository: @public_user_repo)
        latest_database = create(:codeql_database, repository: @public_user_repo)
      end

      assert_equal T.must(superseded_database).created_at, T.must(latest_database).created_at

      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)

      assert_equal 1, CodeqlDatabase.count
      assert_equal T.must(latest_database).id, T.must(CodeqlDatabase.first).id
    end

    test "handles when there are no superseeded databases" do
      CodeqlDatabase.delete_all

      latest_database = create(:codeql_database, repository: @public_user_repo)

      CodeqlDatabaseCleanupJob.perform_now(repository_id: @public_user_repo.id)

      assert_equal 1, CodeqlDatabase.count
      assert_equal latest_database.id, T.must(CodeqlDatabase.first).id
    end

    test "only deletes database that can no longer have active signed URLs" do
      repo = create(:repository, owner: @user)

      # This database and the next-most-recent database are both older than
      # the signed URL lifetime. Therefore any signed URLs for this database
      # will be expired, and all active signed URLs must be for a later database.
      old_db = Timecop.freeze(6.days.ago) { create(:codeql_database, repository: repo) }
      # Even though this database is older than the signed URL lifetime,
      # the next-most-recent database is younger than the signed URL lifetime.
      # Therefore there could still be active signed URLs that were created
      # while this database was the most recent database.
      first_db_past_url_lifetime = Timecop.freeze(5.days.ago) { create(:codeql_database, repository: repo) }
      # This database is younger than the signed URL lifetime. Therefore it
      # may still have active signed URLs.
      young_db = Timecop.freeze(4.hours.ago) { create(:codeql_database, repository: repo) }
      # This is the latest database and thus cannot be deleted.
      latest_db = Timecop.freeze(1.hour.ago) { create(:codeql_database, repository: repo) }

      CodeqlDatabaseCleanupJob.perform_now(repository_id: repo.id)

      assert_nil CodeqlDatabase.find_by(id: old_db.id)
      refute_nil CodeqlDatabase.find_by(id: first_db_past_url_lifetime.id)
      refute_nil CodeqlDatabase.find_by(id: young_db.id)
      refute_nil CodeqlDatabase.find_by(id: latest_db.id)
    end

    test "it shouldn't raise an error when the codeql db record or file in azure cannot be deleted" do
      repo = create(:public_repository, owner: @user)
      database_to_be_deleted = Timecop.freeze(2.weeks.ago) do
        create(:codeql_database, repository: repo, state: :starter, uploader: @user)
      end

      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      path = "/#{database_to_be_deleted.storage_s3_bucket}/#{database_to_be_deleted.storage_s3_key(nil)}"
      assert_storage_policy_delete(database_to_be_deleted, path, delete_status: 500) do
        assert_nothing_raised do
          CodeqlDatabaseCleanupJob.perform_now(repository_id: repo.id)
        end
      end
      assert_equal 1, GitHub.dogstats.increments("code_scanning.codeql_database.failed_deletion").count
      assert_equal 0, GitHub.dogstats.increments("code_scanning.codeql_database.deleted").count
    end
  end
end
