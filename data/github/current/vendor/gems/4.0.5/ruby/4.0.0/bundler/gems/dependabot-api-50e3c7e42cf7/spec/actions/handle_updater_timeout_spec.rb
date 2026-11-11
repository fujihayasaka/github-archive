# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleUpdaterTimeout do
  include ActiveJob::TestHelper

  subject(:handler) { described_class.new(update_job: update_job, event_source: "source") }

  let(:update_job) { nil }
  let(:repo) { update_job&.update_config&.repo }

  context "with a job in processing state" do
    let(:update_job) do
      FactoryBot.create(:update_job, :processing)
    end

    it "transitions the job" do
      expect { handler.run }.
        to change { update_job.reload.current_state }.
        from("processing").to("timed_out")
    end

    it "instruments the timeout" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.timed_out", 1,
        tags: hash_including({
                               event_source: "source",
                             })
      )

      handler.run
    end

    it "enqueues a job to create a time out issue" do
      expect { handler.run }.
        to have_enqueued_job(NotifyGitHubOfFailureJob).
        with(
          update_job: update_job,
          error_hash: {
            "error-type" => "timed_out",
            "error-detail" => nil,
          }
        )
    end

    it "injects a timeout error with error_type timed_out" do
      expect { handler.run }.
        to change { update_job.update_job_errors.count }.from(0).to(1)
      expect(update_job.update_job_errors.last.error_type).to eq("timed_out")
    end

    it "instruments completion of timeout handling" do
      expect(MetricsClient).
        to receive(:count).
        with("updater_timeout.handled", 1, tags: hash_including(runner_type: update_job.runner_type))

      handler.run
    end

    context "when the job has existing errors" do
      before { FactoryBot.create(:update_job_error, update_job: update_job) }

      it "does not inject a timeout error" do
        expect { handler.run }.
          not_to change { update_job.update_job_errors.count }.from(1)
      end

      it "enqueues a job to create an issue with those errors" do
        expect { handler.run }.
          to have_enqueued_job(NotifyGitHubOfFailureJob).
          with(
            update_job: update_job,
            error_hash: {
              "error-type" => "dependency_file_not_evaluatable",
              "error-detail" => { "message" => "My message" },
            },
          )
      end
    end

    it "does not attempt to clean up PR updates by default" do
      expect { handler.run }.
        not_to have_enqueued_job(CancelStalePullRequestUpdate)
    end
  end

  context "with an expired job that is updating a PR" do
    let(:pull_request) { FactoryBot.create(:pull_request, :updating) }
    let!(:update_job) { pull_request.last_transition.update_job }

    before do
      update_job.transition_to!(:enqueued)
      update_job.transition_to!(:processing)
      update_job.update!(expires_at: 1.hour.ago)
    end

    it "transitions the job" do
      expect { handler.run }.
        to change { update_job.reload.current_state }.
        from("processing").to("timed_out")
    end

    it "instruments the timeout" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.timed_out", 1,
        tags: hash_including({
                               trigger: "rebase",
                               event_source: "source",
                             })
      )

      handler.run
    end

    it "delegates PR cleanup to CancelStalePullRequestUpdate" do
      expect { handler.run }.
        to have_enqueued_job(CancelStalePullRequestUpdate).
        with(update_job: update_job)
    end
  end

  context "with a job in enqueued state" do
    let(:update_job) do
      FactoryBot.create(:update_job, :enqueued)
    end

    it "transitions the job to abandoned" do
      expect { handler.run }.
        to change { update_job.reload.current_state }.
        from("enqueued").to("abandoned")
    end

    it "instruments the abandoned state with reason" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.abandoned", 1,
        tags: hash_including({
                               event_source: "source",
                               reason: "job_never_started",
                             })
      )

      handler.run
    end

    it "injects an actions_service_unavailable error" do
      expect { handler.run }.
        to change { update_job.update_job_errors.count }.from(0).to(1)
      expect(update_job.update_job_errors.last.error_type).to eq("actions_service_unavailable")
    end

    it "enqueues a job to create an actions_service_unavailable issue" do
      expect { handler.run }.
        to have_enqueued_job(NotifyGitHubOfFailureJob).
        with(
          update_job: update_job,
          error_hash: {
            "error-type" => "actions_service_unavailable",
            "error-detail" => nil,
          }
        )
    end
  end

  context "with a job in pending state" do
    let(:update_job) do
      FactoryBot.create(:update_job, :pending)
    end

    it "transitions the job through enqueued to abandoned" do
      expect { handler.run }.
        to change { update_job.reload.current_state }.
        from("pending").to("abandoned")
    end

    it "instruments the abandoned state with reason" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.abandoned", 1,
        tags: hash_including({
                               event_source: "source",
                               reason: "job_never_started",
                             })
      )

      handler.run
    end

    it "injects an actions_service_unavailable error" do
      expect { handler.run }.
        to change { update_job.update_job_errors.count }.from(0).to(1)
      expect(update_job.update_job_errors.last.error_type).to eq("actions_service_unavailable")
    end
  end
end
