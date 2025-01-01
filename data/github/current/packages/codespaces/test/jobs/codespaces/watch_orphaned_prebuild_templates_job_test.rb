# typed: true
# frozen_string_literal: true

require "test_helper"

class WatchOrphanedPrebuildTemplatesJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  fixtures do
    @admin = create(:user)
  end

  context "does not queue delete prebuilds by repo job" do
    test "if job feature flag is not enabled" do
      disable_feature_flag(:codespaces_watch_orphaned_prebuild_templates_job)

      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      Codespaces::WatchOrphanedPrebuildTemplatesJob.expects(:perform_later).never

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if repo is soft deleted and no configuration exists" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).never

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if repo is soft deleted and the configuration is already disabled" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration.disable
      configuration.save

      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).never

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if org disables codespaces and no config/template exists" do
      org = create(:organization)
      repo = create(:repository, owner: org, from_example: :simple)


      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).never

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if the repo exists and the repo owner has codespaces enabled" do
      # valid repo and org
      org = create(:codespaces_organization, admin: @admin)
      repo = create(:repository, owner: org, from_example: :simple)


      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).never

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end
  end

  context "queues delete prebuilds by repo job" do
    test "if repo is soft deleted and configuration exists" do
      # create soft deleted repo
      repo = create(:repository, :soft_deleted, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(
        repository_id: repo.id,
      )

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if org disables codespaces and config/template exists" do
      org = create(:organization)
      repo = create(:repository, owner: org, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      template = create(:codespace_prebuild_template, repository: repo)


      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(
        repository_id: repo.id,
      )

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "if repo is hard deleted" do
      repo = create(:repository, from_example: :simple)

      create(:codespace_prebuild_template, repository: repo)

      repo.destroy

      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(
        repository_id: repo.id,
        disable_prebuild_configurations: false,
        hard_delete_configurations: true
      )

      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end

    test "multiple times if multiple repositories are to be cleaned up" do
      hard_deleted_repo = create(:repository, from_example: :simple)
      create(:codespace_prebuild_configuration, repository: hard_deleted_repo)
      hard_deleted_repo.destroy

      disabled_codespaces_org = create(:codespaces_organization, plan: GitHub::Plan.free)
      disable_feature_flag(:codespaces_billing_free, disabled_codespaces_org)
      disabled_codespaces_repo = create(:repository, owner: disabled_codespaces_org, from_example: :simple)
      create(:codespace_prebuild_configuration, repository: disabled_codespaces_repo)
      create(:codespace_prebuild_template, repository: disabled_codespaces_repo)

      valid_repo_org = create(:codespaces_organization, admin: @admin)
      valid_repo = create(:repository, owner: valid_repo_org, from_example: :simple)
      create(:codespace_prebuild_template, repository: valid_repo)

      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(repository_id: disabled_codespaces_repo.id)
      Codespaces::DeletePrebuildsForRepoJob.expects(:perform_later).with(
        repository_id: hard_deleted_repo.id,
        disable_prebuild_configurations: false,
        hard_delete_configurations: true
      )
      Codespaces::WatchOrphanedPrebuildTemplatesJob.perform_now
    end
  end
end unless GitHub.enterprise?
