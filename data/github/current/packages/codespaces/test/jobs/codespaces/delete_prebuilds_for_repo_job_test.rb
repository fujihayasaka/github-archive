# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeletePrebuildsForRepoJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  fixtures do
    enable_feature_flag(:codespaces_delete_prebuilds_for_repo_job)
  end

  context "does not perform template deletion" do
    test "if feature flag is not enabled" do
      disable_feature_flag(:codespaces_delete_prebuilds_for_repo_job)

      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).never

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)
    end

    test "for templates and configs that don't belong to the repository passed to the job" do
      repo = create(:repository, from_example: :simple)

      repo2 = create(:repository, from_example: :simple)

      # create config
      configuration = create(:codespace_prebuild_configuration, repository: repo)

      # create template
      template = create(:codespace_prebuild_template, repository: repo)
      template2 = create(:codespace_prebuild_template, repository: repo, codespace_prebuild_configuration_id: configuration.id)

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).never

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo2.id)
    end

    test "if already handled by configuration template deletion" do
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration_id = configuration.id

      template = create(:codespace_prebuild_template, repository: repo, codespace_prebuild_configuration_id: configuration.id)
      template_id = template.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).once

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)

      assert_equal true, Codespaces::PrebuildConfiguration.find_by(id: configuration_id)&.disabled?
      assert Codespaces::PrebuildTemplate.find_by(id: template_id)
    end
  end

  context "performs template deletion" do
    test "for configuration if feature flag is enabled" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration_id = configuration.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: repo.id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id,
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)
    end

    test "with geos instead of regions" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      geos = %w[
        UsWest
        UsEast
        EuropeWest
      ]

      configuration = create(:codespace_prebuild_configuration, repository: repo, with_geos: geos)
      configuration_id = configuration.id

      regions = Codespaces::Locations::Region.where(geo: geos).map(&:id)
      # checks if configuration.region_names is a subset of regions
      assert_equal (configuration.region_names & regions).size, configuration.region_names.size

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: repo.id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id,
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)
    end

    test "for templates not associated with a configuration" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      template = create(:codespace_prebuild_template, repository: repo)
      template_id = template.id

      template_2 = create(:codespace_prebuild_template, repository: repo)
      template_2_id = template_2.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: template.branch,
        locations: [template.location],
        repository_id: template.repository_id,
        vscs_target: template.vscs_target,
        vscs_target_url: template.vscs_target_url,
        devcontainer_path: template.devcontainer_path,
        configuration_id: template.codespace_prebuild_configuration_id,
      )

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: template_2.branch,
        locations: [template_2.location],
        repository_id: template_2.repository_id,
        vscs_target: template_2.vscs_target,
        vscs_target_url: template_2.vscs_target_url,
        devcontainer_path: template_2.devcontainer_path,
        configuration_id: template_2.codespace_prebuild_configuration_id,
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)
    end

    test "for templates with no configuration id stored" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)

      template = create(:codespace_prebuild_template, repository: repo)

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: configuration.repository_id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id
      )

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: template.branch,
        locations: [template.location],
        repository_id: template.repository_id,
        vscs_target: template.vscs_target,
        vscs_target_url: template.vscs_target_url,
        devcontainer_path: template.devcontainer_path,
        configuration_id: template.codespace_prebuild_configuration_id,
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)
    end
  end

  context "prebuild configuration" do
    test "is disabled after deletion job is queued for the config" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration_id = configuration.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: repo.id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id)

      assert_equal true, Codespaces::PrebuildConfiguration.find_by(id: configuration_id)&.disabled?
    end

    test "is not disabled if disable_prebuild_configurations is false" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration_id = configuration.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: repo.id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id, disable_prebuild_configurations: false)

      assert_equal false, Codespaces::PrebuildConfiguration.find_by(id: configuration_id)&.disabled?
    end

    test "is deleted if hard delete is passed as true" do
      # create soft deleted repo
      repo = create(:repository, active: nil, from_example: :simple)

      configuration = create(:codespace_prebuild_configuration, repository: repo)
      configuration_id = configuration.id

      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later).with(
        branch: configuration.branch,
        locations: configuration.region_names,
        repository_id: repo.id,
        vscs_target: configuration.vscs_target,
        vscs_target_url: configuration.vscs_target_url,
        devcontainer_path: configuration.devcontainer_path,
        configuration_id: configuration.id
      )

      Codespaces::DeletePrebuildsForRepoJob.perform_now(repository_id: repo.id, disable_prebuild_configurations: false, hard_delete_configurations: true)

      assert_nil Codespaces::PrebuildConfiguration.find_by(id: configuration_id)
    end
  end
end unless GitHub.enterprise?
