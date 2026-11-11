# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::MarkAsProcessed do
  include ActiveSupport::Testing::TimeHelpers

  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) do
    { data: { "base-commit-sha": "sha" } }
  end

  context "for a processing update job with a pull request" do
    let(:update_job) { FactoryBot.create(:update_job, :processing, base_commit_sha: nil) }

    let!(:pull_request) do
      FactoryBot.create(:pull_request, update_job: update_job)
    end

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to processed" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("processed")
    end

    it "enqueues a job to lift the update config's rate limit" do
      expect { instance.call }.to have_enqueued_job(ReviewUpdateConfigRateLimit)
    end

    it "instruments the processed job" do
      expect(MetricsClient).to receive(:timing).
        with("mark_as_processed.duration", anything, anything)
      expect(MetricsClient).to receive(:count).
        with("mark_as_processed.completed", 1, anything)
      instance.call
    end

    it "sets the base commit sha" do
      expect { instance.call }.
        to change(update_job, :base_commit_sha).
        from(nil).to("sha")
    end
  end

  context "for a processing update job with a pending pull request" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    let!(:pending_pull_request) do
      FactoryBot.create(:pending_pull_request, update_job: update_job)
    end

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to processed" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("processed")
    end

    it "enqueues a job to lift the update config's rate limit" do
      expect { instance.call }.to have_enqueued_job(ReviewUpdateConfigRateLimit)
    end

    it "instruments the processed job" do
      expect(MetricsClient).to receive(:timing).
        with("mark_as_processed.duration", anything, anything)
      expect(MetricsClient).to receive(:count).
        with("mark_as_processed.completed", 1, anything)
      instance.call
    end
  end

  context "for an update job with no errors or potential pull requests" do
    let(:update_job) do
      FactoryBot.create(:update_job, :processing, github_request_id: 42)
    end
    let(:update_config) { update_job.update_config }
    let(:error_type) { "update_not_possible" }
    let(:error_detail) { nil }

    let(:expected_error_hash) do
      { "error-type" => error_type, "error-detail" => error_detail }
    end

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to processed_with_errors" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("processed_with_errors")
      expect(update_job.last_transition.metadata["errors"]).
        to eq([expected_error_hash])
    end

    it "does not remove the update config's rate limit" do
      expect { instance.call }.
        not_to change { update_config.current_state(force_reload: true) }
    end

    it "delegates issue creation to NotifyGitHubOfFailureJob" do
      expect { instance.call }.
        to have_enqueued_job(NotifyGitHubOfFailureJob).
        with(
          update_job: update_job,
          error_hash: expected_error_hash,
        )
    end

    it "doesn't kick off a CancelStalePullRequestUpdate job" do
      expect { instance.call }.
        not_to have_enqueued_job(CancelStalePullRequestUpdate)
    end

    it "instruments the errored job" do
      expect(MetricsClient).to receive(:timing).
        with("mark_as_processed.duration", anything, anything)
      expect(MetricsClient).to receive(:count).
        with(
          "mark_as_processed.errored", 1,
          tags: hash_including({
                                 error_type: "expected_error",
                                 error_category: "expected_error",
                               })
        )
      instance.call
    end
  end

  context "for an update job with no errors or potential pull requests because it's a rebase" do
    let(:pull_request) do
      FactoryBot.create(:pull_request)
    end

    let(:pull_request_transition) do
      pull_request.transition_to!(:updating)
      pull_request.pull_request_transitions.last
    end

    let(:update_job) do
      FactoryBot.create(
        :update_job,
        :processing,
        github_request_id: 42,
        pull_request_transition: pull_request_transition,
        trigger_type: "rebase"
      )
    end

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to processed" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("processed")
    end

    it "enqueues a job to lift the update config's rate limit" do
      expect { instance.call }.to have_enqueued_job(ReviewUpdateConfigRateLimit)
    end

    it "instruments the processed job" do
      expect(MetricsClient).to receive(:timing).
        with("mark_as_processed.duration", anything, anything)
      expect(MetricsClient).to receive(:count).
        with("mark_as_processed.completed", 1, anything)
      instance.call
    end
  end

  context "multi ecosystem update jobs" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, :active, multi_ecosystem_config:) }
    let(:related_update_config) { create(:update_config, :active, multi_ecosystem_config:) }
    let(:enqueue_scheduled_update_id) { "fixed-uuid" }
    let(:update_jobs) do
      [
        create(:update_job, :processing, update_config:, enqueue_scheduled_update_id:),
        create(:update_job, :processing, update_config: related_update_config, enqueue_scheduled_update_id:),
      ]
    end
    let!(:pull_request) do
      FactoryBot.create(:pull_request, update_job: update_jobs.last)
    end
    let(:context) { { request: request, update_job: update_jobs.last } }

    context "multi_ecosystems feature is disabled and multi-ecosystem jobs have been processed" do
      it { is_expected.to respond_with_status(204) }

      it "does not enqueue CombinePullRequestsAfterJobsCompletion job" do
        expect(CombinePullRequestsAfterJobsCompletion).not_to receive(:perform_later)
        instance.call
      end
    end

    context "multi_ecosystems feature is enabled and multi-ecosystem jobs have been processed" do
      before do
        update_jobs.each do |update_job|
          allow(update_job).to receive(:config_feature_enabled?).and_return(false)
          allow(update_job).to receive(:config_feature_enabled?).with(:multi_ecosystems).and_return(true)
        end
      end

      it "enqueue CombinePullRequestsAfterJobsCompletion job" do
        expect(CombinePullRequestsAfterJobsCompletion).to receive(:perform_later).with(
          associated_update_job_ids: update_jobs.map(&:id),
        ).once
        instance.call
      end

      it { is_expected.to respond_with_status(204) }
    end
  end

  context "for an update job with errors" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }
    let(:update_config) { update_job.update_config }
    let!(:update_job_errors) do
      [
        FactoryBot.create(
          :update_job_error,
          error_type: error_type,
          error_details: error_detail,
          update_job: update_job,
        ),
      ]
    end
    let(:error_type) { "dependency_file_not_evaluatable" }
    let(:error_detail) { nil }

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to processed_with_errors" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("processed_with_errors")
      expect(update_job.last_transition.metadata["errors"]).
        to eq([{ "error-type" => error_type, "error-detail" => error_detail }])
    end

    it "does not remove the update config's rate limit" do
      expect { instance.call }.
        not_to change { update_config.current_state(force_reload: true) }
    end

    it "delegates issue creation to NotifyGitHubOfFailureJob" do
      expect { instance.call }.
        to have_enqueued_job(NotifyGitHubOfFailureJob).
        with(
          update_job: update_job,
          error_hash: update_job_errors.first.error_hash,
        )
    end

    it "doesn't kick off a CancelStalePullRequestUpdate job" do
      expect { instance.call }.
        not_to have_enqueued_job(CancelStalePullRequestUpdate)
    end

    it "instruments the errored job" do
      expect(MetricsClient).to receive(:timing).
        with("mark_as_processed.duration", anything, anything)
      expect(MetricsClient).to receive(:count).
        with(
          "mark_as_processed.errored", 1,
          tags: hash_including({
                                 error_type: "user_error",
                                 error_category: "user_error",
                               })
        )
      instance.call
    end

    context "with a pull request being updated" do
      let(:pull_request) { FactoryBot.create(:pull_request, :updating) }
      let(:update_job) { pull_request.last_transition.update_job }

      before { update_job.transition_to!(:enqueued) }

      before { update_job.transition_to!(:processing) }

      it "delegates PR cleanup to CancelStalePullRequestUpdate" do
        expect { instance.call }.
          to have_enqueued_job(CancelStalePullRequestUpdate).
          with(update_job: update_job)
      end
    end

    context "with non-identical errors that would create the same issue" do
      let(:error_type) { "unknown_error" }
      let!(:update_job_errors) do
        [
          FactoryBot.create(
            :update_job_error,
            error_type: error_type,
            error_details: nil,
            update_job: update_job,
          ),
          FactoryBot.create(
            :update_job_error,
            error_type: error_type,
            error_details: { "message" => "different" },
            update_job: update_job,
          ),
        ]
      end

      it "doesn't create duplicate issues" do
        expect { instance.call }.
          to have_enqueued_job(NotifyGitHubOfFailureJob).once
      end
    end

    context "with non-identical errors that would create different issues" do
      let!(:update_job_errors) do
        [
          FactoryBot.create(
            :update_job_error,
            error_type: "dependency_file_not_evaluatable",
            error_details: nil,
            update_job: update_job,
          ),
          FactoryBot.create(
            :update_job_error,
            error_type: "dependency_file_not_resolvable",
            error_details: nil,
            update_job: update_job,
          ),
        ]
      end

      it "creates separate issues" do
        expect { instance.call }.
          to have_enqueued_job(NotifyGitHubOfFailureJob).twice
      end
    end

    context "with an octokit_unauthorized error" do
      let(:error_type) { "octokit_unauthorized" }

      it "does not update the box size for the update config" do
        expect { instance.call }.
          not_to change(update_config, :required_instance_size)
      end

      it "transitions the update job to pending_retry" do
        expect { instance.call }.
          to change { update_job.current_state(force_reload: true) }.
          from("processing").to("pending_retry")
      end

      context "for a manual triggered job" do
        before do
          update_job.update(trigger_type: "manual")
        end

        it "enqueues a job to retry the update run using high priority" do
          expect(update_job).to receive(:retry!).with(wait: 0).
            and_call_original
          expect { instance.call }.
            to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
            with(update_job)
        end
      end

      context "for an automatic triggered job" do
        before do
          update_job.update(trigger_type: "push")
        end

        it "enqueues a job to retry the update run using low priority" do
          expect(update_job).to receive(:retry!).with(wait: 0).
            and_call_original
          expect { instance.call }.
            to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
            with(update_job)
        end
      end

      context "for a job triggered by vulnerability publishing" do
        before do
          update_job.update(trigger_type: "scan")
        end

        it "enqueues a job to retry the update run using lowest priority" do
          expect(update_job).to receive(:retry!).with(wait: 0).
            and_call_original
          expect { instance.call }.
            to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
            with(update_job)
        end
      end

      it "deletes old update job errors, ready for the retry" do
        expect { instance.call }.
          to change { update_job.update_job_errors.count }.
          from(1).to(0)
      end

      context "with a pull request being updated" do
        let(:pull_request) { FactoryBot.create(:pull_request, :updating) }
        let(:update_job) { pull_request.last_transition.update_job }

        before { update_job.transition_to!(:enqueued) }

        before { update_job.transition_to!(:processing) }

        it "does not enqueue PR cleanup" do
          expect { instance.call }.
            not_to have_enqueued_job(CancelStalePullRequestUpdate)
        end
      end

      context "that has already retried once before" do
        before do
          update_job.transition_to!(
            :processed_with_errors,
            errors: [{ "error-type" => "octokit_unauthorized" }],
          )
        end

        before { update_job.transition_to!(:pending_retry) }

        before { update_job.transition_to!(:enqueued) }

        before { update_job.transition_to!(:processing) }

        it "transitions the update job to processed_with_errors" do
          expect { instance.call }.
            to change { update_job.current_state(force_reload: true) }.
            from("processing").to("processed_with_errors")
        end
      end
    end

    context "with an octokit_rate_limited error" do
      let(:error_type) { "octokit_rate_limited" }
      let(:reset_at) { 1.hour.from_now.to_i }
      let(:reset_range) do
        reset_in = Time.at(reset_at).in_time_zone - Time.now.in_time_zone +
                   180.seconds
        reset_max = reset_in + HandleUpdaterFailure::RateLimitedRetryStrategy::MAX_JITTER
        be_between(reset_in, reset_max)
      end
      let(:error_detail) do
        { "rate-limit-reset" => reset_at }
      end

      it "does not update the box size for the update config" do
        expect { instance.call }.
          not_to change(update_config, :required_instance_size)
      end

      it "transitions the update job to pending_retry" do
        expect { instance.call }.
          to change { update_job.current_state(force_reload: true) }.
          from("processing").to("pending_retry")
      end

      context "for an automatic triggered job" do
        before do
          update_job.update(trigger_type: "push")
        end

        it "enqueues a job to retry the update run using low priority" do
          freeze_time do
            expect(update_job).to receive(:retry!).with(wait: reset_range).
              and_call_original
            expect { instance.call }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
              with(update_job)
          end
        end
      end

      context "for a job triggered by vulnerability publishing" do
        before do
          update_job.update(trigger_type: "scan")
        end

        it "enqueues a job to retry the update run using lowest priority" do
          freeze_time do
            expect(update_job).to receive(:retry!).with(wait: reset_range).
              and_call_original
            expect { instance.call }.
              to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
              with(update_job)
          end
        end
      end

      it "deletes old update job errors, ready for the retry" do
        expect { instance.call }.
          to change { update_job.update_job_errors.count }.
          from(1).to(0)
      end

      context "with a pull request being updated" do
        let(:pull_request) { FactoryBot.create(:pull_request, :updating) }
        let(:update_job) { pull_request.last_transition.update_job }

        before { update_job.transition_to!(:enqueued) }

        before { update_job.transition_to!(:processing) }

        it "does not enqueue PR cleanup" do
          expect { instance.call }.
            not_to have_enqueued_job(CancelStalePullRequestUpdate)
        end
      end

      context "that has not reached the retry limit" do
        before do
          2.times do
            update_job.transition_to!(
              :processed_with_errors,
              errors: [{ "error-type" => "octokit_rate_limited" }],
            )
            update_job.transition_to!(:pending_retry)
            update_job.transition_to!(:enqueued)
            update_job.transition_to!(:processing)
          end
        end

        it "transitions the update job to processed_with_errors" do
          expect { instance.call }.
            to change { update_job.current_state(force_reload: true) }.
            from("processing").to("pending_retry")
        end
      end

      context "that has reached the retry limit" do
        before do
          3.times do
            update_job.transition_to!(
              :processed_with_errors,
              errors: [{ "error-type" => "octokit_rate_limited" }],
            )
            update_job.transition_to!(:pending_retry)
            update_job.transition_to!(:enqueued)
            update_job.transition_to!(:processing)
          end
        end

        it "transitions the update job to processed_with_errors" do
          expect { instance.call }.
            to change { update_job.current_state(force_reload: true) }.
            from("processing").to("processed_with_errors")
        end
      end
    end

    context "with a git dependencies not reachable error" do
      let(:error_type) { "git_dependencies_not_reachable" }
      let(:error_detail) do
        { "dependency-urls" => ["git@github.com:some/dependency"] }
      end

      it "passes detail of the repo to the issue creator" do
        expect { instance.call }.
          to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: update_job_errors.first.error_hash,
          )
      end
    end
  end

  context "for an update job with a timeout error" do
    let(:update_job) { FactoryBot.create(:update_job, :processing, base_commit_sha: "already_set") }
    let(:update_config) { update_job.update_config }
    let!(:update_job_errors) do
      [
        FactoryBot.create(
          :update_job_error,
          error_type: "timed_out",
          update_job: update_job,
        ),
      ]
    end

    it { is_expected.to respond_with_status(204) }

    it "transitions the update job to timed_out" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        from("processing").to("timed_out")
    end

    it "instruments the timeout" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.timed_out", 1,
        tags: hash_including({
                               event_source: "api.mark_as_processed",
                             })
      )

      instance.call
    end

    it "does not set the base commit sha if it was already set" do
      # base_commit_sha would already be set if create_pull_request was called first
      expect { instance.call }.
        not_to change { update_job.reload.base_commit_sha }
    end
  end

  context "for a processing update job with base commit sha greater then 40" do
    let(:params) do
      { data: { "base-commit-sha": "foooooooooooobbbbbbbbbbbbbbbbbbbbbbbbbbbrrrrr" } }
    end

    let(:update_job) { FactoryBot.create(:update_job, :processing, base_commit_sha: nil) }

    let!(:pull_request) do
      FactoryBot.create(:pull_request, update_job: update_job)
    end

    it { is_expected.to respond_with_status(400) }
  end
end
