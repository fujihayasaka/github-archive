# frozen_string_literal: true

require "rails_helper"

require "dependabot/pull_request_creator"
require "dependabot/pull_request_updater"

RSpec.describe "/autofix_suggestion_jobs", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include MonolithSettingsHelper
  include ProximaHelpers

  describe "POST /autofix_suggestion_jobs/:id/sarif" do
    subject(:post_sarif) do
      post(
        "/autofix_suggestion_jobs/#{autofix_suggestion_job.id}/sarif",
        params: params,
        headers: header,
      )
    end

    let(:pull_request) { create(:pull_request) }
    let(:autofix_suggestion_job) { create(:autofix_suggestion_job, pull_request: pull_request) }
    let(:params) { fixture("sarif/styled-components.sarif") }
    let(:header) do
      return { "CONTENT_TYPE" => "application/json" } unless token

      base_64_token = Base64.strict_encode64(token)
      checksum = "0nE82Q"
      {
        "Authorization" => "dependabot-pr_#{base_64_token}#{checksum}",
        "CONTENT_TYPE" => "application/json",
      }
    end

    before do
      # in order to set an expectation on the test object we need to
      # also stub the DB lookup to return this exact object
      allow(AutofixSuggestionJob).to receive(:find_by).
        with(id: autofix_suggestion_job.id).
        and_return(autofix_suggestion_job)
      allow(autofix_suggestion_job).to receive(:complete_github_check_run)
    end

    context "when the token is not set" do
      let(:token) { nil }

      it "returns a 401" do
        post_sarif
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when the token is invalid" do
      let(:token) { "invalid" }

      it "returns a 403" do
        post_sarif
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "when the JSON is invalid" do
      let(:token) { "valid" }
      let(:params) { "[" }

      it "returns a 400" do
        post_sarif
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when the token is valid" do
      let(:token) { "valid" }

      before do
        stub_monolith_feature(:dependabot_autofix, actor: pull_request.repo.monolith_actor)

        pull_request.hashed_token = Base64.strict_encode64(RbNaCl::Hash.sha256(token))
      end

      # NOTE: The autofix experiment is no longer active so the turboscan-client gem has been removed because it blocked
      # upgrading to Ruby 3.4. So Turboscan::Autofix#generate_dependabot_fix now raises immediately.
      # The full autofix code still needs to get cleaned up at some point, including other references to Turboscan.
      it "raises because the Turboscan client has been removed" do
        expect { post_sarif }.to raise_error(Turboscan::Autofix::Error, /no longer active/)
        expect(autofix_suggestion_job).to have_received(:complete_github_check_run).with(
          conclusion: GitHub::CheckRun::Conclusion::FAILURE
        )
      end
    end

    context "with the demo workflow" do
      let(:token) { "valid" }
      let(:github_client) { instance_double("Octokit::Client") }

      before do
        pull_request.repo.enable_feature(:autofix_demo) # rubocop:disable Dependabot/NoLocalFeatureFlags

        pull_request.hashed_token = Base64.strict_encode64(RbNaCl::Hash.sha256(token))
        allow(GitHubHelpers::ClientWithRetries).to receive(:new).and_return(github_client)
        allow(github_client).to receive(:post).
          and_return(nil)
      end

      it "saves the sarif data" do
        expect(autofix_suggestion_job.sarif_content).to be_nil

        post_sarif

        autofix_suggestion_job.reload
        expect(autofix_suggestion_job.sarif_content).to eq(JSON.parse(params))
      end

      it "POSTs the SARIF to Code Scanning" do
        post_sarif
        expect(github_client).to have_received(:post)
        expect(response).to have_http_status(:no_content)
      end

      it "logs the submission" do
        allow(Dependabot::Logger).to receive(:info)
        expect(Dependabot::Logger).
          to receive(:info).
          with(msg: "Submitting SARIF", destination: "Code Scanning")

        post_sarif
      end

      it "records stage successes" do
        expect(autofix_suggestion_job).to receive(:observe_stage).
          with(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE).
          and_call_original
        expect(AutofixSuggestionJob::Stages).to receive(:record_success).
          with(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE)

        expect(autofix_suggestion_job).to receive(:observe_stage).
          with(stage: AutofixSuggestionJob::Stages::SUBMIT_AUTOFIX_REQUEST).
          and_call_original
        expect(AutofixSuggestionJob::Stages).to receive(:record_success).
          with(stage: AutofixSuggestionJob::Stages::SUBMIT_AUTOFIX_REQUEST)

        post_sarif
      end

      it "records stage errors" do
        # in order to set an expectation on the test object we need to
        # also stub the DB lookup to return this exact object
        allow(AutofixSuggestionJob).to receive(:find_by).
          with(id: autofix_suggestion_job.id).
          and_return(autofix_suggestion_job)

        allow(autofix_suggestion_job).to receive(:update!) do
          raise "test"
        end

        expect(AutofixSuggestionJob::Stages).to receive(:record_error).
          with(hash_including(stage: AutofixSuggestionJob::Stages::SUBMIT_AUTOFIX_REQUEST))
        expect(AutofixSuggestionJob::Stages).not_to receive(:record_success).
          with(stage: AutofixSuggestionJob::Stages::SUBMIT_AUTOFIX_REQUEST)

        expect { post_sarif }.to raise_error("test")
      end
    end
  end
end
