# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateScheduledUpdateJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(update_config_id: update_config.id, enqueue_scheduled_update_id: "test-uuid")
  end

  before do
    allow(SecureRandom).to receive(:uuid).and_return("fixed-uuid")
  end

  let(:account) do
    FactoryBot.create(
      :account,
      :active,
    )
  end

  let(:repo) do
    FactoryBot.create(
      :repo,
      account: account,
      config_file_path: ".github/dependabot.yml"
    )
  end

  context "with an update config that is active" do
    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :active,
        :daily,
        repo: repo
      )
    end

    let(:update_job) do
      FactoryBot.create(:update_job, :scheduled)
    end

    it "enqueues an update job" do
      expect { job.perform_now }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end

    it "instruments the update job" do
      expect(MetricsClient).to receive(:count).
        with("scheduled_update.triggered", 1,
             tags: hash_including({
                                    update_schedule: "daily",
                                    trigger: "schedule",
                                    update_type: "version",
                                  }))

      job.perform_now
    end

    context "with no open pull requests" do
      it "doesn't enqueue a PR update job" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end
    end

    context "with an open pull request" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
        )
      end

      it "doesn't enqueue a PR update job by default" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end

      context "when automatic rebases disabled are disabled" do
        before do
          update_config.update!(rebase_strategy: "disabled")
        end

        it "enqueues a PR update job" do
          expect { job.perform_now }.
            to have_enqueued_job(CheckPullRequestForConflictsJob).
            with(
              pull_request: pull_request,
              ignore_rebases_disabled_setting: true,
              event_source: "job.create_scheduled_update",
            )
        end
      end
    end
  end

  context "with an update config that is active but has version updates disabled" do
    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :active,
        :daily,
        repo: repo,
        open_pull_requests_limit: 0
      )
    end

    it "is a noop" do
      assert_no_enqueued_jobs do
        job.perform_now
      end
    end
  end

  context "with an update config id that does not exist" do
    let(:update_config) { instance_double(UpdateConfig, id: 42) }

    it "is a noop" do
      assert_no_enqueued_jobs do
        job.perform_now
      end
    end
  end

  context "with an update config that is active but the account is inactive" do
    let(:account) do
      FactoryBot.create(
        :account,
        :inactive,
      )
    end

    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :daily,
        :active,
        repo: repo
      )
    end

    it "is a noop" do
      assert_no_enqueued_jobs do
        job.perform_now
      end
    end
  end

  context "with an update config that is deleted" do
    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :daily,
        :deleted,
        repo: repo
      )
    end

    it "is a noop" do
      assert_no_enqueued_jobs do
        job.perform_now
      end
    end
  end

  context "pausing updates", feature: :inactivity_pausing do
    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :active,
        :daily,
        repo: repo
      )
    end
    let(:repo) do
      FactoryBot.create(
        :repo,
        account: account,
        config_file_path: ".github/dependabot.yml",
        will_pause_at: will_pause_at
      )
    end

    let(:will_pause_at) { nil }

    describe "when the repo does not have will_pause_at set" do
      it "schedules an update and does not pause the repo" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
      end
    end

    describe "when the repo has will_pause_at set at a timestamp in the past" do
      let(:will_pause_at) { 1.minute.ago }

      it "does not schedule an update and pauses the repo" do
        job.perform_now

        expect(PrioritizedJobs::StartUpdateJob::Low).not_to have_been_enqueued
        expect(PauseRepoJob).to have_been_enqueued
      end
    end

    describe "when the repo has will_pause_at set at a timestamp in the future" do
      let(:will_pause_at) { 1.minute.from_now }

      it "schedules an update and does not pause the repo" do
        job.perform_now

        expect(PrioritizedJobs::StartUpdateJob::Low).to have_been_enqueued
        expect(PauseRepoJob).not_to have_been_enqueued
      end
    end

    describe "when the repo has will_pause_at set at a timestamp in the past and the repo is already paused" do
      let(:will_pause_at) { 1.minute.ago }

      before do
        repo.update!(paused_at: 1.minute.ago)
      end

      it "does not schedule an update and does not unpause the repo" do
        job.perform_now

        expect(PrioritizedJobs::StartUpdateJob::Low).not_to have_been_enqueued
        expect(PauseRepoJob).not_to have_been_enqueued
        expect(repo.reload).to be_paused
      end
    end

    describe "when the repo has will_pause_at set at a timestamp in the future and the repo is already paused" do
      let(:will_pause_at) { 1.minute.from_now }

      before do
        repo.update!(paused_at: 1.minute.ago)
      end

      it "does not schedule an update and does not unpause the repo" do
        job.perform_now

        expect(PrioritizedJobs::StartUpdateJob::Low).not_to have_been_enqueued
        expect(PauseRepoJob).not_to have_been_enqueued
        expect(repo.reload).to be_paused
      end
    end

    describe "for a security update config with a open_pull_request_limit of 0" do
      let(:will_pause_at) { 1.minute.ago }
      let(:update_config) do
        FactoryBot.create(
          :update_config,
          :active,
          :daily,
          repo: repo,
          open_pull_requests_limit: 0
        )
      end

      it "does not schedule an update and pauses the repo" do
        job.perform_now

        expect(PrioritizedJobs::StartUpdateJob::Low).not_to have_been_enqueued
        expect(PauseRepoJob).to have_been_enqueued
      end
    end
  end

  context "with an update config that has not had a successful run producing PRs" do
    before do
      stub_const("BrokenRepoDetection::JOBS_TO_CHECK_FOR_FAILURES", 3)
      FactoryBot.create_list(
        :update_job,
        BrokenRepoDetection::JOBS_TO_CHECK_FOR_FAILURES,
        :processed_with_errors,
        update_config: update_config
      )
      update_config.update_jobs.each do |update_job|
        FactoryBot.create(
          :update_job_error,
          update_job: update_job,
          error_type: "unknown_error"
        )
        FactoryBot.create(
          :update_job_error,
          update_job: update_job,
          error_type: "dependency_files_not_resolvable"
        )
      end
    end

    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :active,
        :daily,
        repo: repo
      )
    end

    it "does not enqueue an update job" do
      allow(Dependabot::Logger).to receive(:info)

      expect { job.perform_now }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
      expect(MetricsClient).to have_received(:increment).
        with("compute_reduction", tags: { initiative: "pause_on_broken_repos" })
      expect(MetricsClient).to have_received(:increment).
        with("broken_update", tags: { error_type: "unknown_error" })
      expect(Dependabot::Logger).to have_received(:info).
        with(hash_including(errors: "unknown_error,dependency_files_not_resolvable"))
    end

    it "created an update job with :no_successful_runs state and coped the first error" do
      expect { job.perform_now }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

      job = update_config.reload.update_jobs.last
      expect(job.current_state).to eq("no_successful_runs")
      expect(job.update_job_errors.count).to eq(1)
      expect(job.update_job_errors.first.error_type).to eq("unknown_error")

      expect(MetricsClient).to have_received(:increment).with("compute_reduction",
                                                              tags: { initiative: "pause_on_broken_repos" })
    end

    it "only creates one update job with :no_successful_runs state" do
      sleep(1) # fixes sorting factory jobs by created_at coming first, on some seeds
      expect do
        described_class.new(update_config_id: update_config.id,
                            enqueue_scheduled_update_id: "test-uuid-1").perform_now
      end.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
      expect do
        described_class.new(update_config_id: update_config.id,
                            enqueue_scheduled_update_id: "test-uuid-2").perform_now
      end.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

      expect(update_config.reload.update_jobs.count { |j| j.current_state == "no_successful_runs" }).to eq(1)
      expect(MetricsClient).to have_received(:increment).with("compute_reduction",
                                                              tags: { initiative: "pause_on_broken_repos" }).twice
    end

    context "but it had no update_job_errors" do
      before do
        FactoryBot.create_list(
          :update_job,
          CreateScheduledUpdateJob::JOBS_TO_CHECK_FOR_FAILURES,
          :processed_with_errors,
          update_config: update_config
        )
      end

      it "is allowed to proceed" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

        expect(update_config.reload.update_jobs.count { |j| j.current_state == "no_successful_runs" }).to eq(0)
        expect(MetricsClient).not_to have_received(:increment).with("compute_reduction",
                                                                    tags: { initiative: "pause_on_broken_repos" })
      end
    end

    context "one of the errors is a pull request limit error" do
      before do
        FactoryBot.create(
          :update_job_error,
          update_job: update_config.update_jobs.first,
          error_type: "open_pull_request_limit_exceeded"
        )
      end

      it "enqueues an update job" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
        expect(MetricsClient).not_to have_received(:increment).with("compute_reduction",
                                                                    tags: { initiative: "pause_on_broken_repos" })
      end
    end
  end

  context "with an update config using dependency groups" do
    let(:update_config) do
      FactoryBot.create(
        :update_config,
        :active,
        :daily,
        repo: repo
      )
    end

    let(:dependency_group) do
      FactoryBot.create(:dependency_group, update_config: update_config)
    end

    context "with no open pull requests" do
      it "doesn't enqueue a job to check any PRs for conflict" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end

      it "doesn't enqueue any scheduled refresh jobs" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledRefreshJob)
      end
    end

    context "with open pull requests and automatic rebasing enabled" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
        )
      end

      let!(:grouped_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      before do
        update_config.update!(rebase_strategy: "auto")
      end

      it "doesn't enqueue a job to check any PRs for conflict" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end

      it "enqueues a scheduled refresh of the group PR" do
        expect { job.perform_now }.
          to have_enqueued_job(CreateScheduledRefreshJob).
          with(pull_request: grouped_pull_request, event_source: "job.create_scheduled_update")

        expect(CreateScheduledRefreshJob).
          not_to have_been_enqueued.
          with(pull_request: pull_request, event_source: "job.create_scheduled_update")
      end
    end

    context "with an open pull requests and automatic rebasing disabled" do
      let!(:pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
        )
      end

      let!(:grouped_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      before do
        update_config.update!(rebase_strategy: "disabled")
      end

      it "enqueues a job to check the non-group PR for conflict" do
        expect { job.perform_now }.
          to have_enqueued_job(CheckPullRequestForConflictsJob).
          with(
            pull_request: pull_request,
            ignore_rebases_disabled_setting: true,
            event_source: "job.create_scheduled_update",
          )

        expect(CheckPullRequestForConflictsJob).
          not_to have_been_enqueued.
          with(
            pull_request: grouped_pull_request,
            ignore_rebases_disabled_setting: true,
            event_source: "job.create_scheduled_update",
          )
      end

      it "enqueues a scheduled refresh of the group PR" do
        expect { job.perform_now }.
          to have_enqueued_job(CreateScheduledRefreshJob).
          with(pull_request: grouped_pull_request, event_source: "job.create_scheduled_update")

        expect(CreateScheduledRefreshJob).
          not_to have_been_enqueued.
          with(pull_request: pull_request, event_source: "job.create_scheduled_update")
      end
    end

    context "with an open grouped pull request that does not have a dependency group" do
      before do
        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: nil
        )
      end

      it "does not enqueue a refresh of the group PR" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledRefreshJob)
      end
    end

    context "with an open grouped pull request that has a deleted dependency group" do
      before do
        dependency_group.delete

        FactoryBot.create(
          :pull_request,
          update_config: update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      it "does not enqueue a refresh of the group PR" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CreateScheduledRefreshJob)
      end
    end
  end

  context "when the open pull request limit is exceeded" do
    let(:update_config) do
      create(
        :update_config,
        :active,
        :daily,
        repo: repo,
        open_pull_requests_limit: 5,
        rebase_strategy: "auto"
      )
    end

    before do
      create_list(:pull_request, 5, update_config: update_config)
    end

    context "when the update config has auto rebase_strategy" do
      it "does not enqueue rebase jobs for open PRs" do
        expect { job.perform_now }.
          not_to have_enqueued_job(CheckPullRequestForConflictsJob)
      end
    end

    context "when the update config has disabled rebase_strategy" do
      before do
        update_config.update!(rebase_strategy: "disabled")
      end

      it "enqueues rebase jobs for open PRs" do
        expect { job.perform_now }.
          to have_enqueued_job(CheckPullRequestForConflictsJob).
          exactly(5).times
      end
    end

    it "changes the job state to processed_with_errors" do
      job.perform_now

      update_job = update_config.reload.update_jobs.last
      expect(update_job.current_state).to eq("cancelled")
    end

    it "creates an update job error" do
      job.perform_now

      update_job = update_config.reload.update_jobs.last
      expect(update_job.update_job_errors.count).to eq(1)
      expect(update_job.update_job_errors.last.error_type).to eq("open_pull_request_limit_exceeded")
      expect(update_job.update_job_errors.last.error_details).to eq("Open PR limit reached or exceeded")
    end
  end

  describe "group update logging" do
    let(:update_config) { create(:update_config, :grouped_update, :active, :daily, repo:) }

    before do
      allow(Dependabot::Logger).to receive(:info)
    end

    context "when creating a group update job" do
      it "logs group creation context" do
        job.perform_now

        expect(Dependabot::Logger).
          to have_received(:info).with(hash_including(
                                         :msg => "Created group update job",
                                         :"code.namespace" => "CreateScheduledUpdateJob",
                                         :"gh.dependabot_api.update_job.group_creation_context" => "scheduled",
                                         "gh.dependabot_api.update_job.grouping_requested" => true,
                                         "gh.dependabot_api.update_job.dependency_groups_count" => 1,
                                         :"gh.dependabot_api.update_job.dependency_groups" => [{
                                           applies_to: "version-updates",
                                           name: "all-the-things",
                                           rules: { "patterns" => ["*"] },
                                           sort_order: nil,
                                         }]
                                       ))
      end
    end

    context "when creating an individual update job" do
      let(:update_config) do
        FactoryBot.create(:update_config, :active, :daily, repo: repo)
      end

      it "logs individual job creation context" do
        job.perform_now

        expect(Dependabot::Logger).to have_received(:info).with(
          hash_including(
            msg: "Created individual update job",
            "code.namespace": "CreateScheduledUpdateJob",
            "gh.dependabot_api.update_job.group_creation_context": "individual"
          )
        )
      end
    end

    context "when group update config is broken" do
      let(:dependency_group) { FactoryBot.create(:dependency_group, name: "test-group", update_config: update_config) }

      before do
        stub_const("BrokenRepoDetection::JOBS_TO_CHECK_FOR_FAILURES", 3)
        FactoryBot.create_list(
          :update_job,
          BrokenRepoDetection::JOBS_TO_CHECK_FOR_FAILURES,
          :processed_with_errors,
          update_config: update_config
        )
        update_config.update_jobs.each do |update_job|
          FactoryBot.create(
            :update_job_error,
            update_job: update_job,
            error_type: "dependency_resolution_failed"
          )
        end
      end

      it "emits grouped broken config metric" do
        allow(Dependabot::Logger).to receive(:info)

        job.perform_now

        expect(MetricsClient).to have_received(:increment).
          with("grouped_update.config_broken", hash_including(
                                                 tags: hash_including(
                                                   grouped_update: true,
                                                   group_count: 1,
                                                   group_names: "all-the-things",
                                                   error_type: "dependency_resolution_failed"
                                                 )
                                               ))
      end

      it "enhances existing broken_update metric with group context" do
        allow(Dependabot::Logger).to receive(:info)

        job.perform_now

        expect(MetricsClient).to have_received(:increment).
          with("broken_update", hash_including(
                                  tags: hash_including(
                                    error_type: "dependency_resolution_failed",
                                    grouped_update: true,
                                    group_count: 1,
                                    group_names: "all-the-things"
                                  )
                                ))
      end

      it "enhances compute_reduction metric with group context" do
        allow(Dependabot::Logger).to receive(:info)

        job.perform_now

        expect(MetricsClient).to have_received(:increment).
          with("compute_reduction", hash_including(
                                      tags: hash_including(
                                        initiative: "pause_on_broken_repos",
                                        grouped_update: true,
                                        group_count: 1,
                                        group_names: "all-the-things"
                                      )
                                    ))
      end
    end

    context "when group update config is paused" do
      before do
        repo.update!(paused_at: Time.current)
      end

      it "emits grouped config paused metric" do
        allow(Dependabot::Logger).to receive(:info)

        job.perform_now

        expect(MetricsClient).to have_received(:increment).
          with("grouped_update.config_paused", hash_including(
                                                 tags: hash_including(
                                                   grouped_update: true,
                                                   group_count: 1,
                                                   group_names: "all-the-things"
                                                 )
                                               ))
      end
    end
  end
end
