# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class RemoveContentWarningJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    @staff = create(:staff_admin_user)

    @repo1 = create(:repository, name: "repo1")
    @fork1 = create(:repository, name: "fork1", parent: @repo1)
    @fork2 = create(:repository, name: "fork2", parent: @repo1)

    @repo2 = create(:repository, name: "repo2")

    @options = {
      actor: @staff,
      forks: false,
      notify_fork_owners: true,
      instructions: nil,
    }

    # Start repo1, fork2, fork2 out with content warnings
    @repo1.set_content_warning("violent_content", **@options, forks: true)
  end

  setup do
    @jobs_unable_to_lock = 0
    GlobalInstrumenter.subscribe("jobs.lock-not-acquired") do |_event, _start, _finish, _id, payload|
      @jobs_unable_to_lock += 1 if payload[:job].class == RemoveContentWarningJob
    end
  end

  private def reload_repos
    @repo1.reload
    @fork1.reload
    @fork2.reload
  end

  private def jobs_enqueued
    GitHub.dogstats.increments("active_job.enqueued")
      .map { |i| i.tags }
      .count { |t| t.include?("class:remove_content_warning_job") }
  end

  private def jobs_performed
    GitHub.dogstats.increments("active_job.performed")
      .map { |i| i.tags }
      .count { |t| t.include?("class:remove_content_warning_job") }
  end

  private def perform_remove_content_warning_job(&block)
    perform_enqueued_jobs(only: [RemoveContentWarningJob, ApplicationDeliveryJob], &block)
  end

  test "removes content warnings from individual repos" do
    assert @repo1.content_warning?
    assert @fork1.content_warning?
    assert @fork2.content_warning?

    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    reload_repos

    refute @repo1.content_warning?
    assert @fork1.content_warning?
    assert @fork2.content_warning?

    assert_equal jobs_enqueued, 1
  end

  test "removes content warnings from forks" do
    assert @repo1.content_warning?
    assert @fork1.content_warning?
    assert @fork2.content_warning?

    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options, forks: true) }
    reload_repos

    refute @repo1.content_warning?
    refute @fork1.content_warning?
    refute @fork2.content_warning?
  end

  test "runs multiple jobs sequentially for the same repo" do
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 3
    assert_equal @jobs_unable_to_lock, 0
  end

  test "doesn't run multiple jobs concurrently for the same repo" do
    RemoveContentWarningJob.perform_later(@repo1, **@options)
    RemoveContentWarningJob.perform_later(@repo1, **@options)
    RemoveContentWarningJob.perform_later(@repo1, **@options)

    perform_remove_content_warning_job

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 1
    assert_equal @jobs_unable_to_lock, 2
  end

  test "doesn't run multiple jobs concurrently for the same network" do
    RemoveContentWarningJob.perform_later(@fork1, **@options)
    RemoveContentWarningJob.perform_later(@repo1, **@options)
    RemoveContentWarningJob.perform_later(@fork2, **@options)

    perform_remove_content_warning_job

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 1
    assert_equal @jobs_unable_to_lock, 2
  end

  test "runs multiple jobs concurrently for different networks" do
    RemoveContentWarningJob.perform_later(@repo1, **@options)
    RemoveContentWarningJob.perform_later(@repo2, **@options)

    perform_remove_content_warning_job

    assert_equal jobs_enqueued, 2
    assert_equal jobs_performed, 2
    assert_equal @jobs_unable_to_lock, 0
  end

  test "doesn't send emails" do
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    assert_equal 0, ActionMailer::Base.deliveries.size
  end

  test "doesn't send emails for content warning removal" do
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    perform_enqueued_jobs(only: [ApplyContentWarningJob, ApplicationDeliveryJob]) do
      ApplyContentWarningJob.perform_later(@repo1, "malicious_content", **@options)
    end
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "it writes a log when skipping a content warning update" do
    assert_logged("Body" => "Skipping content warning update for #{@repo1.full_name} because it is already set to ") do
      perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
      perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options) }
    end
  end

  test "it recalculates trending repos once after removing a content warning from a network" do
    Stafftools::NetworkPrivilege.expects(:recalculate_trending_repos).once
    perform_remove_content_warning_job { RemoveContentWarningJob.perform_later(@repo1, **@options, forks: true) }
  end
end
