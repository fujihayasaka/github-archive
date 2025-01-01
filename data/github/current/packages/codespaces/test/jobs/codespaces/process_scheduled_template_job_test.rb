# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ProcessScheduledTemplateJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  fixtures do
    @repo = create(:repository, owner: create(:organization), from_example: :simple)

    # create configuration
    @prebuild_template_config1 = Codespaces::PrebuildConfiguration.new(
      vscs_target: "production",
      repository: @repo,
      branch: @repo.default_branch
    )

    locations = %w[
      EuropeWest
      SoutheastAsia
    ]
    @prebuild_template_config1.build_initial_locations(locations: locations)
    @prebuild_template_config1.trigger = :schedule

    # create schedules
    @prebuild_template_config1.build_delivery_times(
      delivery_days: %w[Monday Tuesday Wednesday Thursday],
      delivery_times: ["12:00 AM"],
      time_zone_name: "America/New_York")

    @prebuild_template_config1.save!
    @prebuild_template_schedule1 = @prebuild_template_config1.schedules[0]
    @prebuild_template_schedule1.next_delivery_at = 1.day.ago
    @prebuild_template_schedule1.save!
    @prebuild_template_schedule2 = @prebuild_template_config1.schedules[1]
    @prebuild_template_schedule3 = @prebuild_template_config1.schedules[2]
    @prebuild_template_schedule4 = @prebuild_template_config1.schedules[3]

  end

  test "do nothing if record has already been processed" do
    next_delivery_at = @prebuild_template_schedule1.next_delivery_at

    # Manually update next delivery at to indicate record has already been processed
    Codespaces::PrebuildTemplateCreationSchedule.find(@prebuild_template_schedule1.id).update_next_delivery_at
    updated_next_delivery_at = Codespaces::PrebuildTemplateCreationSchedule.find_by(id: @prebuild_template_schedule1.id)

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).never

    Codespaces::ProcessScheduledTemplateJob.perform_now(template_schedule_id: @prebuild_template_schedule1.id, queued_next_delivery_at: next_delivery_at)

    current_next_delivery_at = Codespaces::PrebuildTemplateCreationSchedule.find_by(id: @prebuild_template_schedule1.id)

    # next delivery at is not updated again if record was already processed
    assert_equal(updated_next_delivery_at, current_next_delivery_at)
  end

  test "workflow is not queued if prebuild configuration trigger is not schedule" do
    @prebuild_template_config1.update(trigger: Codespaces::PrebuildConfiguration::DEFAULT_TRIGGER)

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).never

    Codespaces::ProcessScheduledTemplateJob.perform_now(template_schedule_id: @prebuild_template_schedule1.id, queued_next_delivery_at: @prebuild_template_schedule1.next_delivery_at)
  end

  test "verify dynamic workflow is triggered with correct values" do
    prebuild_template_schedule3_next_delivery = @prebuild_template_schedule3.next_delivery_at

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
      repository: @repo,
      branch: @prebuild_template_config1.branch,
      locations: @prebuild_template_config1.region_names,
      commit_sha: @repo.heads.find(@prebuild_template_config1.branch).sha,
      concurrency_modifier:  @prebuild_template_config1.id.to_s,
      vscs_target: @prebuild_template_config1.vscs_target,
      vscs_target_url: @prebuild_template_config1.vscs_target_url,
      configuration: @prebuild_template_config1,
      devcontainer_path: nil,
      previous_sha: nil,
    )

    Codespaces::ProcessScheduledTemplateJob.perform_now(template_schedule_id: @prebuild_template_schedule3.id, queued_next_delivery_at: prebuild_template_schedule3_next_delivery)
  end

  test "verify next_delivery_at time is updated after record is processed" do
    prebuild_template_schedule1_original_next_delivery = @prebuild_template_schedule1.next_delivery_at

    Codespaces::ProcessScheduledTemplateJob.perform_now(template_schedule_id: @prebuild_template_schedule1.id, queued_next_delivery_at: prebuild_template_schedule1_original_next_delivery)

    prebuild_template_schedule_1 = Codespaces::PrebuildTemplateCreationSchedule.find(@prebuild_template_schedule1.id)

    # verify next_delivery_at time is updated
    refute_equal prebuild_template_schedule1_original_next_delivery, prebuild_template_schedule_1.next_delivery_at
  end


  test "verify null reference isn't thrown when calculating commit sha if branch is deleted" do
    repo2 = create(:repository, owner: create(:organization), from_example: :simple)

    # create configuration
    prebuild_configuration = Codespaces::PrebuildConfiguration.new(
      vscs_target: "production",
      repository: repo2,
      branch: repo2.default_branch
    )

    locations = [
      "EuropeWest",
    ]

    prebuild_configuration.build_initial_locations(locations: locations)
    prebuild_configuration.trigger = :schedule

    # create schedules
    prebuild_configuration.build_delivery_times(
      delivery_days: ["Monday"],
      delivery_times: ["12:00 AM"],
      time_zone_name: "America/New_York")

    prebuild_configuration.save!
    prebuild_template_schedule = prebuild_configuration.schedules[0]

    # delete branch
    repo2.heads.find(prebuild_configuration.branch).delete(repo2.owner)

    Codespaces::CreatePrebuildTemplateDynamicWorkflowJob.expects(:perform_later).with(
      repository: repo2,
      branch: prebuild_configuration.branch,
      locations: prebuild_configuration.region_names,
      commit_sha: nil,
      concurrency_modifier: prebuild_configuration.id.to_s,
      vscs_target: prebuild_configuration.vscs_target,
      vscs_target_url: prebuild_configuration.vscs_target_url,
      configuration: prebuild_configuration,
      devcontainer_path: nil,
      previous_sha: nil,
    )

    Codespaces::ProcessScheduledTemplateJob.perform_now(template_schedule_id: prebuild_template_schedule.id, queued_next_delivery_at: prebuild_template_schedule.next_delivery_at)
  end
end
