# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class DeletePrebuildTemplatesJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @org = create(:codespaces_organization, admin: @user)
    @repo = create(:repository, owner: @org)
    @locations = %w[EastUs WestUs2]
    @job_args = {
      branch: "master",
      locations: @locations,
      repository_id: @repo.id,
    }
  end

  test "increments datadog if the job is forced to exit" do
    Codespaces::DeletePrebuildTemplates.expects(:call).raises(Aqueduct::Worker::JobKilled.new)
    Codespaces::DeletePrebuildTemplatesJob.any_instance.expects(:retry_job)
    Codespaces::DeletePrebuildTemplatesJob.perform_now(**@job_args)

    assert_dogstats_increment "codespaces.delete_prebuild_templates_job.dirty_exit", tags: ["vscs_target:production"]
  end

  test "calls DeletePrebuildTemplates with expected arguments" do
    Codespaces::DeletePrebuildTemplates.expects(:call).with(
      branch: "master",
      locations: @locations,
      repository_id: @repo.id,
      vscs_target: :production,
      vscs_target_url: nil,
      devcontainer_path: nil,
      configuration_id: nil
    )

    Codespaces::DeletePrebuildTemplatesJob.perform_now(**@job_args)
  end

  test "increments datadog with the correct tags" do
    Codespaces::DeletePrebuildTemplates.expects(:call).once

    Codespaces::DeletePrebuildTemplatesJob.perform_now(**@job_args)

    tags = [
      "class:codespaces/delete_prebuild_templates_job",
      "vscs_target:production",
    ]
    assert_dogstats_increment "active_job.performed", tags: tags
  end
end
