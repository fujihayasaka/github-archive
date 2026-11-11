# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::MarkOldProcessingJobsAsTimedOut, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class }

  let(:backlog_metric_key) do
    "scheduled_jobs.mark_old_processing_jobs_as_timed_out.backlog"
  end

  context "with a job that recently started processing" do
    let!(:update_job) { FactoryBot.create(:update_job, :processing) }

    it "doesn't transition the job" do
      expect { job.perform_now }.
        not_to change { update_job.reload.current_state }
    end
  end

  context "with a job that is processed" do
    let!(:update_job) { FactoryBot.create(:update_job, :processed, :expired) }

    it "doesn't transition the job" do
      expect { job.perform_now }.
        not_to change { update_job.reload.current_state }
    end

    context "which is encountered by the job due to a race condition" do
      before do
        # Simulate a row becoming processed after the job query
        # has fired by stubbing an ActiveRecord::Relation containing
        # a processed job.
        allow_any_instance_of(job).to receive(:old_processing_update_jobs).
          and_return(UpdateJob.where(id: update_job.id))

        update_job.update_config.update!(package_manager: "npm_and_yarn")
      end

      it "doesn't transition the job" do
        expect { job.perform_now }.
          to not_change { update_job.reload.current_state }.
          and not_change {
            update_job.reload.update_config.required_instance_size
          }
      end
    end
  end

  context "with a job that has been processing for a long time" do
    let!(:update_job) do
      FactoryBot.create(:update_job, :processing, :expired)
    end

    it "transitions the job" do
      expect { job.perform_now }.
        to change { update_job.reload.current_state }.
        from("processing").to("timed_out")
    end

    it "instruments the timeout" do
      expect(MetricsClient).to receive(:count).with(
        "mark_as_processed.timed_out", 1,
        tags: hash_including({
                               event_source: "job.mark_old_processing_jobs_as_timed_out",
                             })
      )

      job.perform_now
    end
  end

  context "when a limit is set" do
    before do
      FactoryBot.create(:update_job, :processing)
      FactoryBot.create_list(:update_job, 2, :processing, :expired)
    end

    it "transitions only the specified number of expired jobs " do
      expect { job.perform_now(limit: 1) }.
        to change { UpdateJob.in_state(:processing).expired.count }.
        from(2).to(1)
    end

    it "gauges the remaining backlog as 1" do
      expect(MetricsClient).
        to receive(:gauge).with(backlog_metric_key, 1)

      job.perform_now(limit: 1)
    end
  end
end
