# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleFailedActionRunJob, type: :job do
  include ActiveJob::TestHelper

  # These values correspond to fixtures generated from dsp-testing/dependabot-actions-webhook-test
  subject(:job) do
    described_class.new(workflow_run_id: workflow_run_id,
                        workflow_job_conclusion: workflow_job_conclusion)
  end

  let(:github_repo_id) { 410261783 }
  let(:workflow_run_id) { 1272965441 }
  let(:workflow_job_conclusion) { nil }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:workflow_run_status) { 200 }
  let(:workflow_run_body) { fixture("github_responses/workflow_run/complete_conclusion_failure.json") }
  let(:workflow_run_url) do
    "https://api.github.com/repositories/#{github_repo_id}/actions/runs/#{workflow_run_id}"
  end

  # Happy path tests
  context "the repository has an update job that should be marked as errored" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processing,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "creates an UpdateJobError on the job" do
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
    end

    it "transitions the job to processed_with_errors" do
      expect { job.perform_now }.
        to change { update_job.current_state(force_reload: true) }.from("processing").to("processed_with_errors")
    end
  end

  context "the repository has an enqueued update job that should be marked as errored" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :enqueued,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "creates an UpdateJobError on the job" do
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
    end

    it "transitions the job to processed_with_errors" do
      expect { job.perform_now }.
        to change { update_job.current_state(force_reload: true) }.from("enqueued").to("processed_with_errors")
    end
  end

  context "the repository has a job that has already been processed" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processed,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.current_state(force_reload: true) }.from("processed")
    end
  end

  context "the repository has an update job that should be marked as timed out" do
    let(:workflow_job_conclusion) { :RESULT_CANCELLED }
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processing,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "creates an UpdateJobError on the job" do
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
    end

    it "transitions the job to processed_with_errors" do
      expect { job.perform_now }.
        to change { update_job.current_state(force_reload: true) }.from("processing").to("timed_out")
    end
  end

  context "the repository has a job that has already been processed_with_errors" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processed_with_errors,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.current_state(force_reload: true) }.from("processed_with_errors")
    end
  end

  context "the repository has a job that has already timed out" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :timed_out,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.current_state(force_reload: true) }.from("timed_out")
    end
  end

  context "the repository does not have a job that matches the workflow run external_id" do
    let(:workfow_run_external_id) { SecureRandom.uuid }

    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processing,
                        :on_gh_actions,
                        actions_external_id: workfow_run_external_id)
    end

    before do
      allow(Dependabot::Logger).to receive(:error)
    end

    it "logs an error" do
      job.perform_now

      expect(Dependabot::Logger).to have_received(:error)
    end
  end
end
