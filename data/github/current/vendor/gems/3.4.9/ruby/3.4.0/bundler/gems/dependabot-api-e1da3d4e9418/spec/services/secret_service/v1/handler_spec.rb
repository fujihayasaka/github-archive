# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecretService::V1::Handler do
  let(:service) do
    DependabotApi::V1::SecretServiceService.new(described_class.new)
  end

  describe "#get_secret" do
    let(:workflow_run_id) { 123 }
    let(:req) { instance_double("Request", workflow_run_id: workflow_run_id) }

    context "when workflow_run_id is blank" do
      it "returns an invalid_argument error" do
        req = instance_double("Request", workflow_run_id: "")
        response = described_class.new.get_secret(req, {})
        expect(response.code).to eq(:invalid_argument)
        expect(response.msg).to eq("workflow_run_id is not provided")
      end
    end

    context "when workflow_run_id is provided" do
      let(:update_job) do
        FactoryBot.create(:update_job, :enqueued, actions_workflow_run_id: workflow_run_id)
      end
      let(:token_data) do
        {
          external_job_token: {
            job_token: "job_token",
            hashed_token: "hashed_token",
          },
          external_cred_token: {
            cred_token: "cred_token",
            hashed_token: "hashed_cred_token",
          },
        }
      end

      before do
        allow(GenerateJobCredTokens).to receive(:new).and_return(
          instance_double("GenerateJobCredTokens", run: token_data)
        )
      end

      context "when the job is in the enqueued state" do
        before do
          allow(update_job).to receive(:in_state?).with(:enqueued).and_return(true)
        end

        it "updates the job and cred hashed tokens and returns the job and cred tokens" do
          response = described_class.new.get_secret(req, {})
          expect(update_job.reload.hashed_token).to eq("hashed_token")
          expect(update_job.reload.hashed_credentials_token).to eq("hashed_cred_token")
          expect(response).to eq({ job_token: "job_token", cred_token: "cred_token" })
        end
      end

      %i(
        pending
        processing
        cancelled
        pending_retry
      ).each do |state|
        context "when the job is in the #{state} state" do
          let(:update_job) do
            FactoryBot.create(:update_job, state, actions_workflow_run_id: workflow_run_id)
          end

          before do
            allow(update_job).to receive(:in_state?).with(state).and_return(false)
          end

          it "does not update the job and returns Twirp::Error.failed_precondition error" do
            response = described_class.new.get_secret(req, {})
            expect(response.code).to eq(:failed_precondition)
            expect(response.msg).to eq("Job is not in the enqueued state. Current state: #{state}")
          end
        end
      end

      %i(
        abandoned
        processed
        processed_with_errors
        timed_out
      ).each do |state|
        context "when the job is in the #{state} state" do
          let(:update_job) do
            FactoryBot.create(:update_job, state, actions_workflow_run_id: workflow_run_id)
          end

          before do
            allow(update_job).to receive(:in_state?).with(state).and_return(false)
            allow(Dependabot::Logger).to receive(:info)
          end

          it "ignores the job and logs the ignored job" do
            response = described_class.new.get_secret(req, {})
            expect(Dependabot::Logger).to have_received(:info).with(
              msg: "Ignoring job due to its state",
              "code.namespace": "SecretService::V1::Handler",
              "gh.actions.workflow_run.id": workflow_run_id,
              "job.id": update_job.id,
              "job.state": state.to_s,
              detail: "Job is not in the enqueued state to be processed."
            )
            expect(response.msg).to eq("Job is not in the enqueued state. Current state: #{state}")
          end
        end
      end
    end

    context "when the UpdateJob is not found" do
      before do
        allow(UpdateJob).to receive(:find_by!).and_raise(ActiveRecord::RecordNotFound)
      end

      xit "raises a Twirp::Error.not_found error" do
        response = described_class.new.get_secret(req, {})
        expect(response.code).to eq(:not_found)
        expect(response.msg).to eq("UpdateJob not found for workflow_run_id: #{workflow_run_id}")
      end

      it "returns default creds for autofix" do
        response = described_class.new.get_secret(req, {})
        expect(response).to eq({
                                 job_token: Prius.get(:dependabot_autofix_npm_token),
                                 cred_token: "invalid",
                               })
      end

      context "and there's a workflow run that gives a PR" do
        before do
          pr = FactoryBot.create(:pull_request)
          pr.hashed_token = "hello"
          pr.actions_workflow_run_id = workflow_run_id
        end

        it "returns backup creds for autofix" do
          response = described_class.new.get_secret(req, {})
          expect(response[:cred_token]).to start_with(PullRequest::DEPENDABOT_PR_TOKEN_PREFIX)
        end
      end
    end
  end
end
