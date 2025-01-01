# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class MigrateTagProtectionsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin, plan: "business_plus")

    @random_org_user = create(:user)
    @org.add_member(@random_org_user)

    RepositoryTagProtectionState::allow_creation_for_tests do
      @repos = []
      (0..9).each do |i|
        repo = create(:repository, name: "repo#{i}", owner: @org)

        ["*", "v*.*", "foo", "*.release", "d/e/f"]
          .each { |pattern| repo.create_tag_protection_state(pattern:) }

        @repos.push(repo)
      end
    end
  end

  test "job does nothing if kill_switch is enabled" do
    enable_feature_flag(:kill_migrate_tag_protections_job)

    before_count = RepositoryTagProtectionState.where(enabled: 1).count
    MigrateTagProtectionsJob.perform_now(last_migrated_repo_id: 0, dry_run: false)
    after_count = RepositoryTagProtectionState.where(enabled: 1).count

    assert_equal before_count, after_count
  end

  test "job processes entire repositories in same run, regardless of smaller batch size" do
    disable_feature_flag(:kill_migrate_tag_protections_job)

    # First two repos have 10 tag protections between them. Job should process whole repos in one run, even
    # though batch size is set to 8. NOTE: job is only runing once here because we don't call perform_enqueued_jobs()

    stub_const(MigrateTagProtectionsJob, :BATCH_SIZE, 8) do
      before_count = RepositoryTagProtectionState.where(enabled: 1).count
      MigrateTagProtectionsJob.perform_now(last_migrated_repo_id: 0, dry_run: false)
      after_count = RepositoryTagProtectionState.where(enabled: 1).count

      assert_equal before_count - 10, after_count

      # Auto-migrated repos should have exactly 2 rulesets
      (0..1).each { |i| assert_equal 2, @repos[i].rulesets.count }
      (2..9).each { |i| assert_equal 0, @repos[i].rulesets.count }
    end
  end

  test "job requeues itself and processes all repositories > last_migrated_repo_id" do
    disable_feature_flag(:kill_migrate_tag_protections_job)

    stub_const(MigrateTagProtectionsJob, :BATCH_SIZE, 8) do
      before_count = RepositoryTagProtectionState.where(enabled: 1).count

      perform_enqueued_jobs(only: [MigrateTagProtectionsJob]) do
        MigrateTagProtectionsJob.perform_now(last_migrated_repo_id: @repos[1].id, dry_run: false)
      end

      after_count = RepositoryTagProtectionState.where(enabled: 1).count

      # First two repos have 10 tag protections between them
      assert_equal 10, after_count

      # Auto-migrated repos should have exactly 2 rulesets
      (0..1).each { |i| assert_equal 0, @repos[i].rulesets.count }
      (2..9).each { |i| assert_equal 2, @repos[i].rulesets.count }
    end
  end

  test "job processes only specified repos is a list of IDs is provided" do
    disable_feature_flag(:kill_migrate_tag_protections_job)

    stub_const(MigrateTagProtectionsJob, :BATCH_SIZE, 8) do
      before_count = RepositoryTagProtectionState.where(enabled: 1).count

      perform_enqueued_jobs(only: [MigrateTagProtectionsJob]) do
        MigrateTagProtectionsJob.perform_now(only_repo_ids: [@repos[3].id, @repos[6].id], dry_run: false)
      end

      after_count = RepositoryTagProtectionState.where(enabled: 1).count

      # Two repos have 10 tag protections between them
      assert_equal before_count - 10, after_count

      # Auto-migrated repos should have exactly 2 rulesets
      [3, 6].each { |i| assert_equal 2, @repos[i].rulesets.count }
      [0, 1, 2, 4, 5, 7, 8, 9].each { |i| assert_equal 0, @repos[i].rulesets.count }
    end
  end
end
