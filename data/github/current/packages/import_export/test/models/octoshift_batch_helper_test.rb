# typed: true
# frozen_string_literal: true

require "test_helper"

class OctoshiftBatchHelperTest < GitHub::TestCase

  fixtures do
    @target_repo = create(:repository)
    @source_repo = create(:repository)
    @octoshift_id = SecureRandom.uuid
  end

  context "TargetRepoState" do
    test "fetching non existent state initializes an empty state" do
      state = OctoshiftBatchHelper::TargetRepoState.fetch(@target_repo.full_name)
      assert_nil(state.current_octoshift_migration_id)
      assert_equal(0, state.current_cursor)
    end

    test "allows setting the current migration guid" do
      state = OctoshiftBatchHelper::TargetRepoState.fetch(@target_repo.full_name)
      state.set_current_octoshift_migration_id(@octoshift_id)

      updated_state = OctoshiftBatchHelper::TargetRepoState.fetch(@target_repo.full_name)
      assert_equal(updated_state.current_octoshift_migration_id, @octoshift_id)
    end

    test "allows setting the current cursor" do
      state = OctoshiftBatchHelper::TargetRepoState.fetch(@target_repo.full_name)

      assert_equal(0, state.current_cursor)
      state.set_current_cursor(10)

      updated_state = OctoshiftBatchHelper::TargetRepoState.fetch(@target_repo.full_name)
      assert_equal(10, updated_state.current_cursor)
    end
  end

  context "MigrationState" do
    test "fetching non existent state initializes an empty state" do
      state = OctoshiftBatchHelper::MigrationState.fetch(@octoshift_id)
      assert_nil(state.target_repo_nwo)
      assert_nil(state.source_repo_url)
      assert_equal(0, state.current_cursor)
      assert_equal(0, state.next_cursor)
    end

    test "fetching from a migration guid works" do
      url = Faker::Internet.url
      migration_guid = SecureRandom.uuid
      OctoshiftBatchHelper::MigrationExportLink.create(migration_guid, @octoshift_id)

      OctoshiftBatchHelper::MigrationState.create(@octoshift_id, @target_repo.full_name, url, 0)
      persisted_state = OctoshiftBatchHelper::MigrationState.fetch_from_migration_guid(migration_guid)
      assert_equal(@target_repo.full_name, persisted_state.target_repo_nwo)
      assert_equal(url, persisted_state.source_repo_url)
      assert_equal(0, persisted_state.current_cursor)
      assert_equal(0, persisted_state.next_cursor)
    end

    test "create persists data" do
      url = Faker::Internet.url
      OctoshiftBatchHelper::MigrationState.create(@octoshift_id, @target_repo.full_name, url, 0)

      persisted_state = OctoshiftBatchHelper::MigrationState.fetch(@octoshift_id)
      assert_equal(@target_repo.full_name, persisted_state.target_repo_nwo)
      assert_equal(url, persisted_state.source_repo_url)
      assert_equal(0, persisted_state.current_cursor)
      assert_equal(0, persisted_state.next_cursor)
    end

    test "set_next_cursor updates the next cursor" do
      OctoshiftBatchHelper::MigrationState.create(@octoshift_id, @target_repo.full_name, Faker::Internet.url, 0)

      persisted_state = OctoshiftBatchHelper::MigrationState.fetch(@octoshift_id)
      assert_equal(0, persisted_state.next_cursor)
      persisted_state.set_next_cursor(10)

      updated_state = OctoshiftBatchHelper::MigrationState.fetch(@octoshift_id)
      assert_equal(10, updated_state.next_cursor)
    end
  end

  context "MigrationExportLink" do
    test "saves and fetches data" do
      migration_guid = SecureRandom.uuid
      assert_nil OctoshiftBatchHelper::MigrationExportLink.fetch(migration_guid)

      OctoshiftBatchHelper::MigrationExportLink.create(migration_guid, @octoshift_id)

      assert_equal @octoshift_id, OctoshiftBatchHelper::MigrationExportLink.fetch(migration_guid)
    end
  end
end
