# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class UpdatePrebuildTemplateVersionsJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple)
    @location = "WestUs2"
    @maximum_template_versions = 2
    @prebuild_configuration = create(
      :codespace_prebuild_configuration,
      repository: @repo,
      branch: @repo.default_branch,
      maximum_template_versions: @maximum_template_versions,
      with_locations: [@location])
    @job_args = {
      prebuild_configuration_id: @prebuild_configuration.id,
      repository: @repo,
      location: @location,
    }
  end

  context "perform" do
    test "increments datadog if the job is forced to exit" do

      Codespaces::UpdatePrebuildTemplateVersions.expects(:call).raises(Aqueduct::Worker::JobKilled.new)
      Codespaces::UpdatePrebuildTemplateVersionsJob.any_instance.expects(:retry_job)
      Codespaces::UpdatePrebuildTemplateVersionsJob.perform_now(**@job_args)

      assert_dogstats_increment "codespaces.update_prebuild_template_versions_job.dirty_exit", tags: ["vscs_target:production", "location:WestUs2"]
    end

    test "calls UpdatePrebuildTemplateVersions with expected arguments" do
      Codespaces::UpdatePrebuildTemplateVersions.expects(:call).with(
        prebuild_configuration_id: @prebuild_configuration.id,
        location: @location
      )

      Codespaces::UpdatePrebuildTemplateVersionsJob.perform_now(**@job_args)
    end

    test "increments datadog with the correct tags" do
      Codespaces::UpdatePrebuildTemplateVersions.expects(:call).once
      Codespaces::UpdatePrebuildTemplateVersionsJob.perform_now(**@job_args)

      tags = [
        "class:codespaces/update_prebuild_template_versions_job",
        "vscs_target:production",
        "location:WestUs2",
      ]
      assert_dogstats_increment "active_job.performed", tags: tags
    end
  end
end
