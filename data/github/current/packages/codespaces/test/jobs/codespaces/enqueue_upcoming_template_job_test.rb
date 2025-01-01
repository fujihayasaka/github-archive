# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class EnqueueUpcomingTemplateJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include CodespacesPlanFixtures

  fixtures do
    @repo = create(:repository, owner: create(:organization), from_example: :simple)

    # create prebuild configuration with schedule trigger
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
    @prebuild_template_config1.build_delivery_times(
      delivery_days: %w[Monday Tuesday Wednesday],
      delivery_times: ["12:00 AM"],
      time_zone_name: "America/New_York")

    @prebuild_template_config1.save!
    @prebuild_template_schedule1 = @prebuild_template_config1.schedules[0]
    @prebuild_template_schedule2 = @prebuild_template_config1.schedules[1]
    @prebuild_template_schedule3 = @prebuild_template_config1.schedules[2]
  end

  test "does not enqueue process_scheduled_template_job when nothing is scheduled before 10 minutes from now" do
    @prebuild_template_schedule1.next_delivery_at = 11.minutes.from_now(Time.now.utc)
    @prebuild_template_schedule1.save!

    @prebuild_template_schedule2.next_delivery_at = 15.minutes.from_now(Time.now.utc)
    @prebuild_template_schedule2.save!

    @prebuild_template_schedule3.next_delivery_at = 1.day.from_now(Time.now.utc)
    @prebuild_template_schedule3.save!

    Codespaces::ProcessScheduledTemplateJob.expects(:perform_later).never

    Codespaces::EnqueueUpcomingTemplateJob.perform_now
  end

  test "enqueues process_scheduled_template_job for records scheduled before 10 minutes from now" do
    prebuild_template_config2 = create_prebuild_configuration
    prebuild_template_schedule4 = prebuild_template_config2.schedules[0]

    @prebuild_template_schedule1.next_delivery_at = 10.minutes.ago(Time.now.utc)
    @prebuild_template_schedule1.save!

    @prebuild_template_schedule2.next_delivery_at = 15.minutes.from_now(Time.now.utc)
    @prebuild_template_schedule2.save!

    # create some with the same next_delivery_at
    next_delivery_at = 5.minutes.from_now(Time.now.utc)
    @prebuild_template_schedule3.next_delivery_at = next_delivery_at
    @prebuild_template_schedule3.save!
    prebuild_template_schedule4.next_delivery_at = next_delivery_at
    prebuild_template_schedule4.save!

    Codespaces::EnqueueUpcomingTemplateJob.perform_now

    assert_enqueued_with(job: Codespaces::ProcessScheduledTemplateJob, at: @prebuild_template_schedule1.next_delivery_at, args: [template_schedule_id: @prebuild_template_schedule1.id, queued_next_delivery_at: @prebuild_template_schedule1.next_delivery_at])
    assert_enqueued_with(job: Codespaces::ProcessScheduledTemplateJob, at: @prebuild_template_schedule3.next_delivery_at, args: [template_schedule_id: @prebuild_template_schedule3.id, queued_next_delivery_at: @prebuild_template_schedule3.next_delivery_at])
    assert_enqueued_with(job: Codespaces::ProcessScheduledTemplateJob, at: prebuild_template_schedule4.next_delivery_at, args: [template_schedule_id: prebuild_template_schedule4.id, queued_next_delivery_at: prebuild_template_schedule4.next_delivery_at])
  end

  test "skips schedules with disabled prebuild configurations" do
    @prebuild_template_config1.state = :disabled
    @prebuild_template_config1.save!

    @prebuild_template_schedule1.next_delivery_at = 10.minutes.ago(Time.now.utc)
    @prebuild_template_schedule1.save!
    @prebuild_template_schedule2.next_delivery_at = 12.minutes.ago(Time.now.utc)
    @prebuild_template_schedule2.save!

    Codespaces::ProcessScheduledTemplateJob.expects(:perform_later).never

    Codespaces::EnqueueUpcomingTemplateJob.perform_now
  end

  test "only enqueues ProcessScheduledTemplateJob for enabled prebuild configurations" do
    prebuild_template_config2 = create_prebuild_configuration
    prebuild_template_config2.state = :disabled
    prebuild_template_config2.save!

    # configuration disabled
    prebuild_template_schedule4 = prebuild_template_config2.schedules[0]
    prebuild_template_schedule4.next_delivery_at = 10.minutes.ago(Time.now.utc)
    prebuild_template_schedule4.save!

    # configuration enabled
    @prebuild_template_schedule1.next_delivery_at = 5.minutes.ago(Time.now.utc)
    @prebuild_template_schedule1.save!
    @prebuild_template_schedule2.next_delivery_at = 10.minutes.ago(Time.now.utc)
    @prebuild_template_schedule2.save!

    Codespaces::EnqueueUpcomingTemplateJob.perform_now

    assert_enqueued_with(job: Codespaces::ProcessScheduledTemplateJob, at: @prebuild_template_schedule1.next_delivery_at, args: [template_schedule_id: @prebuild_template_schedule1.id, queued_next_delivery_at: @prebuild_template_schedule1.next_delivery_at])
    assert_enqueued_with(job: Codespaces::ProcessScheduledTemplateJob, at: @prebuild_template_schedule2.next_delivery_at, args: [template_schedule_id: @prebuild_template_schedule2.id, queued_next_delivery_at: @prebuild_template_schedule2.next_delivery_at])
  end

  test "increments datadog if the job is forced to exit" do
    @prebuild_template_schedule1.next_delivery_at = 4.minutes.from_now(Time.now.utc)
    @prebuild_template_schedule1.save!

    Codespaces::ProcessScheduledTemplateJob.expects(:set).raises(Aqueduct::Worker::JobKilled.new)

    Codespaces::EnqueueUpcomingTemplateJob.perform_now

    assert_dogstats_increment 1, "codespaces.enqueue_upcoming_template_job.dirty_exit"
  end

  def create_prebuild_configuration
    # create prebuild configuration with schedule trigger
    prebuild_template_config2 = Codespaces::PrebuildConfiguration.new(
      vscs_target: "ppe",
      repository: @repo,
      branch: @repo.default_branch
    )

    locations = [
      "EuropeWest"
    ]

    prebuild_template_config2.build_initial_locations(locations: locations)
    prebuild_template_config2.trigger = :schedule
    prebuild_template_config2.build_delivery_times(
      delivery_days: ["Wednesday"],
      delivery_times: ["12:00 AM"],
      time_zone_name: "America/New_York")

    prebuild_template_config2.save!

    prebuild_template_config2
  end
end unless GitHub.enterprise?
