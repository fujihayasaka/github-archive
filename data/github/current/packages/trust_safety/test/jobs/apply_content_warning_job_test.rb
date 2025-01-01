# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class ApplyContentWarningJobTest < GitHub::TestCase
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
  end

  setup do
    @jobs_unable_to_lock = 0
    GlobalInstrumenter.subscribe("jobs.lock-not-acquired") do |_event, _start, _finish, _id, payload|
      @jobs_unable_to_lock += 1 if payload[:job].class == ApplyContentWarningJob
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
      .count { |t| t.include?("class:apply_content_warning_job") }
  end

  private def jobs_performed
    GitHub.dogstats.increments("active_job.performed")
      .map { |i| i.tags }
      .count { |t| t.include?("class:apply_content_warning_job") }
  end

  private def perform_apply_content_warning_job(&block)
    perform_enqueued_jobs(only: [ApplyContentWarningJob, ApplicationDeliveryJob], &block)
  end

  test "applies content warnings to individual repos" do
    refute @repo1.content_warning?
    refute @fork1.content_warning?
    refute @fork2.content_warning?

    perform_apply_content_warning_job do
      ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)
    end
    reload_repos

    assert @repo1.content_warning?
    refute @fork1.content_warning?
    refute @fork2.content_warning?

    assert_equal jobs_enqueued, 1
  end

  test "applies content warnings to forks" do
    refute @repo1.content_warning?
    refute @fork1.content_warning?
    refute @fork2.content_warning?

    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options, forks: true) }
    reload_repos

    assert @repo1.content_warning?
    assert @fork1.content_warning?
    assert @fork2.content_warning?
  end

  test "it applies content warnings with subcategories" do
    refute @repo1.content_warning?

    perform_apply_content_warning_job do
      ApplyContentWarningJob.perform_later(@repo1, "mis_dis_information", "medical_scientific", "foo bar", **@options)
    end
    reload_repos

    assert @repo1.content_warning?
  end


  test "runs multiple jobs sequentially for the same repo" do
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 3
    assert_equal @jobs_unable_to_lock, 0
  end

  test "doesn't run multiple jobs concurrently for the same repo" do
    ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)
    ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)
    ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)

    perform_apply_content_warning_job

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 1
    assert_equal @jobs_unable_to_lock, 2
  end

  test "doesn't run multiple jobs concurrently for the same network" do
    ApplyContentWarningJob.perform_later(@fork1, "violent_content", **@options)
    ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)
    ApplyContentWarningJob.perform_later(@fork2, "violent_content", **@options)

    perform_apply_content_warning_job

    assert_equal jobs_enqueued, 3
    assert_equal jobs_performed, 1
    assert_equal @jobs_unable_to_lock, 2
  end

  test "runs multiple jobs concurrently for different networks" do
    ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options)
    ApplyContentWarningJob.perform_later(@repo2, "violent_content", **@options)

    perform_apply_content_warning_job

    assert_equal jobs_enqueued, 2
    assert_equal jobs_performed, 2
    assert_equal @jobs_unable_to_lock, 0
  end

  test "doesn't send emails if the repo's content warning hasn't changed" do
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "it sends emails if the repo's content warning has changed" do
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "malicious_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    assert_equal 3, ActionMailer::Base.deliveries.size
  end

  test "it sends emails for forks if their content warning hasn't changed" do
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@fork1, "violent_content", **@options) }
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options, forks: true) }
    assert_equal 3, ActionMailer::Base.deliveries.size
  end

  test "it writes a log when skipping a content warning update" do
    assert_logged("Body" => "Skipping content warning update for #{@repo1.full_name} because it is already set to violent_content") do
      perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
      perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options) }
    end
  end

  test "it recalculates trending repos once after applying a content warning to a network" do
    Stafftools::NetworkPrivilege.expects(:recalculate_trending_repos).once
    perform_apply_content_warning_job { ApplyContentWarningJob.perform_later(@repo1, "violent_content", **@options, forks: true) }
  end
end
