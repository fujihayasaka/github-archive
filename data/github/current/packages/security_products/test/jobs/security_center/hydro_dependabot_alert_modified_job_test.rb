# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  class HydroDependabotAlertModifiedJobTest < GitHub::TestCase
    include DogstatsTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @org = create :organization
    end

    setup do
      # referencing the job class forces it to load, so it can be looked up by queue name
      @queue = SecurityCenter::HydroDependabotAlertModifiedJob.queue_name
      @schema = "github.security_alerts.v1.RepositoryVulnerabilityAlertLifecycleEvent"

      SecurityFeatures.stubs(:dependabot_alerts_enabled_for_instance?).returns(true)
    end

    test "it enqueues repo sync job" do
      repo = create(:repository, owner: @org)

      RepositorySyncJob
      .expects(:enqueue_once_per_interval)
      .with do |**options|
        kwargs = options[:kwargs]
        kwargs[:repository_id] == repo.id &&
        kwargs[:source_event] == "#{@schema}#create" &&
        kwargs[:feature_type] == "dependabot_alerts" &&
        kwargs[:event_timestamp].present? &&
        options[:interval] == 60 &&
        options[:run_at_beginning_of_interval] == false &&
        options[:unique_id] == ActiveJob::LockingJob::DEFAULT_LOCK_STRINGIFY_PROC.call(repository_id: repo.id, feature_type: "dependabot_alerts")
      end
      .once

      message = {
        action: "create",
        repository_id: repo.id,
      }
      perform_hydro_message_job(message, schema: @schema, queue: @queue)
    end

    test "it enqueues only once within debounce interval" do
      repo = create(:repository, owner: @org)

      message = {
        action: "create",
        repository_id: repo.id,
      }

      assert_enqueued_jobs(1, only: RepositorySyncJob) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
      end
    end

    test "it enqueues again after debounce interval" do
      repo = create(:repository, owner: @org)

      message = {
        action: "create",
        repository_id: repo.id,
      }

      assert_enqueued_jobs(1, only: RepositorySyncJob) do
        perform_hydro_message_job(message, schema: @schema, queue: @queue)
        Timecop.travel(1.minute) do
          perform_hydro_message_job(message, schema: @schema, queue: @queue)
        end
      end
    end

    test "it enqueues again for different repository" do
      repo1 = create(:repository, owner: @org)
      repo2 = create(:repository, owner: @org)

      assert_enqueued_jobs(2, only: RepositorySyncJob) do
        perform_hydro_message_job({ action: "create", repository_id: repo1.id }, schema: @schema, queue: @queue)
        perform_hydro_message_job({ action: "create", repository_id: repo2.id }, schema: @schema, queue: @queue)
      end
    end
  end
end
