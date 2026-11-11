# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::AuditEnqueuedUpdateJobs, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  before do
    allow(MetricsClient).to receive(:gauge)
  end

  context "with a recently created enqueued update job" do
    let!(:update_job) { FactoryBot.create(:update_job, :enqueued) }

    before { allow(Dependabot::Logger).to receive(:info) }

    it "doesn't log anything" do
      job.perform_now
      expect(Dependabot::Logger).not_to have_received(:info)
    end

    it "gauges the number of stagnant jobs as 0" do
      job.perform_now

      expect(MetricsClient).
        to have_received(:gauge).with(anything, 0)
    end

    it "doesn't re-enqueue anything" do
      expect { job.perform_now }.
        not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)

      expect(update_job.current_state(force_reload: true)).
        to eq("enqueued")
    end
  end

  context "with update jobs that are enqueued for over a day" do
    let!(:update_job1) do
      job = FactoryBot.create(:update_job, :enqueued, trigger_type: :push)
      job.last_transition.update!(created_at: 25.hours.ago)
      job
    end

    let!(:update_job2) do
      job = FactoryBot.create(:update_job, :enqueued, trigger_type: :push)
      job.last_transition.update!(created_at: 25.hours.ago)
      job
    end

    before { allow(Dependabot::Logger).to receive(:info) }

    it "gauges the number of stagnant jobs" do
      job.perform_now

      expect(MetricsClient).
        to have_received(:gauge).with(anything, 2)
      expect(MetricsClient).
        to have_received(:increment).with(/audit_enqueued_update_jobs/).twice
    end

    it "logs the jobs" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "Job is over a day old and hasn't started processing.",
               "code.namespace": "ScheduledJobs::AuditEnqueuedUpdateJobs",
               "gh.repo.id": update_job1.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job1.id,
               "gh.dependabot_api.update_config.id": update_job1.update_config.id,
               "gh.owner.id": update_job1.update_config.account.github_id,
               "gh.dependabot_api.update_job.created_at": update_job1.created_at,
               "gh.dependabot_api.update_job.trigger_type": update_job1.trigger_type,
             ))

      expect(Dependabot::Logger).
        to have_received(:info).
        with(a_hash_including(
               msg: "Job is over a day old and hasn't started processing.",
               "code.namespace": "ScheduledJobs::AuditEnqueuedUpdateJobs",
               "gh.repo.id": update_job2.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job2.id,
               "gh.dependabot_api.update_config.id": update_job2.update_config.id,
               "gh.owner.id": update_job2.update_config.account.github_id,
               "gh.dependabot_api.update_job.created_at": update_job2.created_at,
               "gh.dependabot_api.update_job.trigger_type": update_job2.trigger_type,
             ))
    end

    it "re-enqueues the jobs" do
      expect { job.perform_now }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).twice

      expect(update_job1.current_state(force_reload: true)).
        to eq("pending")
      expect(update_job2.current_state(force_reload: true)).
        to eq("pending")
    end

    context "and one of the jobs is now processing" do
      before { update_job1.transition_to!(:processing) }

      it "gauges the number of stagnant jobs excluding the processing job" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(anything, 1)
        expect(MetricsClient).
          to have_received(:increment).with(/viable/).once
      end

      it "does not re-enqueue the processing job" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

        expect(update_job1.current_state(force_reload: true)).
          to eq("processing")

        expect(update_job2.current_state(force_reload: true)).
          to eq("pending")
      end
    end

    context "and one of the jobs is over three days old" do
      before { update_job1.update!(created_at: 73.hours.ago) }

      it "gauges the number of stagnant jobs" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(anything, 2)
        expect(MetricsClient).
          to have_received(:increment).with(/viable/).once
        expect(MetricsClient).
          to have_received(:increment).with(/abandoned/).once
      end

      it "abandon the three day old job instead of retrying" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

        expect(update_job1.current_state(force_reload: true)).
          to eq("abandoned")

        expect(update_job2.current_state(force_reload: true)).
          to eq("pending")
      end
    end

    context "and one of the jobs is manually triggered" do
      before { update_job1.update(trigger_type: :manual) }

      it "gauges the number of stagnant jobs" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(anything, 2)
        expect(MetricsClient).
          to have_received(:increment).with(/viable/).once
        expect(MetricsClient).
          to have_received(:increment).with(/abandoned/).once
      end

      it "abandon the manual job instead of retrying" do
        expect { job.perform_now }.
          to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).once

        expect(update_job1.current_state(force_reload: true)).
          to eq("abandoned")

        expect(update_job2.current_state(force_reload: true)).
          to eq("pending")
      end
    end

    context "and a job targeting self-hosted runners has gone stale" do
      before { update_job1.update(runner_type: UpdateJob::RUNNER_SELF_HOSTED, created_at: 25.hours.ago) }

      it "excludes the self-hosted runner from the metrics" do
        job.perform_now

        expect(MetricsClient).
          to have_received(:gauge).with(anything, 2)
        expect(MetricsClient).
          to have_received(:increment).with(/viable/).once
        expect(MetricsClient).
          not_to have_received(:increment).with(/abandoned/)
      end

      it "transitions the stale job to abandoned" do
        job.perform_now

        expect(update_job1.current_state(force_reload: true)).
          to eq("abandoned")
      end

      it "adds an error to the stale job" do
        job.perform_now

        added_error = update_job1.reload.last_error
        expect(added_error.error_type).
          to eq("self_hosted_runner_unavailable")
      end
    end
  end
end
