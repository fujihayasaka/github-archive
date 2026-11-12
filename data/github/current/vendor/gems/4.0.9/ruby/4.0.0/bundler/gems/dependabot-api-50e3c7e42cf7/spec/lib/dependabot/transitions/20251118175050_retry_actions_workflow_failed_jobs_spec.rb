# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20251118175050_retry_actions_workflow_failed_jobs.rb"
RSpec.describe "RetryActionsWorkflowFailedJobs" do
  include ActiveSupport::Testing::TimeHelpers

  let(:transition) do
    Dependabot::Transitions::RetryActionsWorkflowFailedJobs.new(dry_run: false)
  end

  let(:dry_run_transition) do
    Dependabot::Transitions::RetryActionsWorkflowFailedJobs.new
  end

  let(:start_time) { Time.parse("2025-11-17 00:00:00 UTC") }
  let(:end_time) { Time.parse("2025-11-17 19:00:00 UTC") }

  before do
    # Time-travel to avoid issues with future dates
    travel_to Time.parse("2025-11-18 00:00:00 UTC")
  end

  describe "#perform" do
    context "with jobs that meet the criteria" do
      let!(:repo) { create(:repo) }
      let!(:update_config) { create(:update_config, repo: repo) }

      let!(:job_with_workflow_image_error) do
        create(:update_job,
               update_config: update_config,
               command: :security,
               created_at: start_time + 1.hour).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_image"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_image")
        end
      end

      let!(:job_with_workflow_updater_error) do
        create(:update_job,
               update_config: update_config,
               command: :security,
               created_at: start_time + 2.hours).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_updater"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_updater")
        end
      end

      context "write" do
        it "retries jobs with actions_workflow_image and actions_workflow_updater errors" do
          expect do
            transition.perform
          end.to change {
                   job_with_workflow_image_error.reload.current_state
                 }.from("processed_with_errors").to("pending_retry").
            and change {
                  job_with_workflow_updater_error.reload.current_state
                }.from("processed_with_errors").to("pending_retry")
        end
      end

      context "dry run" do
        it "does not retry jobs in dry run mode" do
          expect do
            dry_run_transition.perform
          end.not_to change { job_with_workflow_image_error.reload.current_state }

          expect(job_with_workflow_image_error.current_state).to eq("processed_with_errors")
          expect(job_with_workflow_updater_error.current_state).to eq("processed_with_errors")
        end
      end
    end

    context "with jobs that should be excluded" do
      let!(:repo) { create(:repo) }
      let!(:update_config) { create(:update_config, repo: repo) }

      let!(:job_before_time_range) do
        create(:update_job,
               update_config: update_config,
               command: :security,
               created_at: start_time - 1.hour).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_image"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_image")
        end
      end

      let!(:job_after_time_range) do
        create(:update_job,
               update_config: update_config,
               command: :security,
               created_at: end_time + 1.hour).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_image"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_image")
        end
      end

      let!(:non_security_job) do
        create(:update_job,
               update_config: update_config,
               command: :version,
               created_at: start_time + 1.hour).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_image"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_image")
        end
      end

      let!(:job_with_different_error) do
        create(:update_job,
               update_config: update_config,
               command: :security,
               created_at: start_time + 1.hour).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["dependency_file_not_found"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "dependency_file_not_found")
        end
      end

      let!(:job_with_newer_update_run) do
        update_config_with_newer_run = create(:update_config, repo: repo)

        # Create the job from the incident window first (lower ID)
        old_job = create(:update_job,
                         update_config: update_config_with_newer_run,
                         command: :security,
                         created_at: start_time + 1.hour,
                         pull_request_transition_id: nil).tap do |job|
          job.transition_to!(:enqueued)
          job.transition_to!(:processing)
          job.transition_to!(:processed_with_errors, errors: ["actions_workflow_image"])
          create(:update_job_error,
                 update_job: job,
                 error_type: "actions_workflow_image")
        end

        # Create a newer update run after the incident window (higher ID)
        create(:update_job,
               update_config: update_config_with_newer_run,
               command: :security,
               created_at: end_time + 2.hours,
               pull_request_transition_id: nil)

        old_job
      end

      context "write" do
        it "does not retry jobs outside the criteria" do
          initial_states = {
            job_before_time_range: job_before_time_range.current_state,
            job_after_time_range: job_after_time_range.current_state,
            non_security_job: non_security_job.current_state,
            job_with_different_error: job_with_different_error.current_state,
            job_with_newer_update_run: job_with_newer_update_run.current_state,
          }

          transition.perform

          expect(job_before_time_range.reload.current_state).to eq(initial_states[:job_before_time_range])
          expect(job_after_time_range.reload.current_state).to eq(initial_states[:job_after_time_range])
          expect(non_security_job.reload.current_state).to eq(initial_states[:non_security_job])
          expect(job_with_different_error.reload.current_state).to eq(initial_states[:job_with_different_error])
          expect(job_with_newer_update_run.reload.current_state).to eq(initial_states[:job_with_newer_update_run])
        end
      end
    end
  end
end
