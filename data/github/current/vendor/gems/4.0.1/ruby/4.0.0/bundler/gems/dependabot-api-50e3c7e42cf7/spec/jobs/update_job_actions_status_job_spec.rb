# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobActionsStatusJob, type: :job do
  include ActiveJob::TestHelper

  # These values correspond to fixtures generated from dsp-testing/dependabot-actions-webhook-test
  subject(:job) do
    described_class.new(update_job_id: update_job_id)
  end

  let(:github_repo_id) { 410261783 }
  let(:workflow_run_id) { 1272965441 }
  let(:workflow_job_conclusion) { nil }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:workflow_run_status) { 200 }
  let(:workflow_run_body) { fixture("github_responses/workflow_run/complete_conclusion_failure.json") }
  let(:workflow_run_url) do
    "https://internal-api.service.iad.github.net/repositories/#{github_repo_id}/actions/runs/#{workflow_run_id}"
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, workflow_run_url).
      to_return(status: workflow_run_status, body: workflow_run_body, headers: json_header)
  end

  # Happy path tests
  context "the repository has an update job that should be marked as errored" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processing,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end
    let(:update_job_id) { update_job.id }
    let(:github_repo_id) { update_job.repo.github_id }

    it "creates an UpdateJobError on the job" do
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
    end

    it "transitions the job to processed_with_errors" do
      expect { job.perform_now }.
        to change { update_job.reload.current_state }.from("processing").to("processed_with_errors")
    end
  end

  context "the repository has a job that has already been processed" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processed,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    let(:update_job_id) { update_job.id }
    let(:github_repo_id) { update_job.repo.github_id }

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.reload.current_state }.from("processed")
    end
  end

  context "the repository has a job that has already been processed_with_errors" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processed_with_errors,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    let(:update_job_id) { update_job.id }
    let(:github_repo_id) { update_job.repo.github_id }

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.reload.current_state }.from("processed_with_errors")
    end
  end

  context "the repository has a job that has already timed out" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :timed_out,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end

    let(:update_job_id) { update_job.id }
    let(:github_repo_id) { update_job.repo.github_id }

    it "does not create an UpdateJobError on the job" do
      expect { job.perform_now }.not_to change { update_job.update_job_errors.count }.from(0)
    end

    it "does not modify the job state" do
      expect { job.perform_now }.
        not_to change { update_job.reload.current_state }.from("timed_out")
    end
  end

  context "the workflow run raises a 404" do
    let(:update_job) do
      FactoryBot.create(:update_job,
                        :processing,
                        :on_gh_actions,
                        actions_workflow_run_id: workflow_run_id)
    end
    let(:update_job_id) { update_job.id }
    let(:github_repo_id) { update_job.repo.github_id }

    let(:workflow_run_status) { 404 }

    it "creates an UpdateJobError on the job" do
      expect { job.perform_now }.to change { update_job.update_job_errors.count }.from(0).to(1)
    end

    it "transitions the job to processed_with_errors" do
      expect { job.perform_now }.
        to change { update_job.reload.current_state }.from("processing").to("processed_with_errors")
    end
  end
end
