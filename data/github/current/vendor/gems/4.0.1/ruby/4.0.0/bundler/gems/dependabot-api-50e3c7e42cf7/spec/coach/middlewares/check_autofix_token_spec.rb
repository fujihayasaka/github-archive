# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::CheckAutofixToken do
  subject(:instance) { described_class.new(context, null_middleware, config) }

  let(:config) { {} }
  let(:context) do
    {
      request: instance_double(
        ActionDispatch::Request,
        headers: headers,
        params: params,
      ),
    }
  end
  let(:received_token) { external_pr_token }
  let(:headers) { { "Authorization" => received_token } }
  let(:params) { { id: autofix_suggestion_job_id } }

  let(:pr_token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_pr_token) { Base64.strict_encode64(pr_token) }
  let(:hashed_pr_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(pr_token)) }
  let(:pr_token_checksum) { Base62.encode(Zlib.crc32(base64_pr_token)).rjust(6, Base62::PRIMITIVES[0]) }
  let(:external_pr_token) do
    PullRequest::DEPENDABOT_PR_TOKEN_PREFIX +
      base64_pr_token +
      pr_token_checksum
  end

  let(:autofix_suggestion_job_id) { 10 }
  let!(:autofix_suggestion_job) do
    FactoryBot.create(
      :autofix_suggestion_job,
      id: autofix_suggestion_job_id,
      pull_request: pull_request,
    )
  end

  let(:pull_request) do
    FactoryBot.create(
      :pull_request,
      hashed_token: hashed_pr_token,
    )
  end

  before do
    # in order to set any expectations on the test object we need to
    # also stub the DB lookup to return this exact object
    allow(AutofixSuggestionJob).to receive(:find_by).and_call_original
    allow(AutofixSuggestionJob).to receive(:find_by).
      with(id: autofix_suggestion_job.id).
      and_return(autofix_suggestion_job)
    allow(autofix_suggestion_job).to receive(:complete_github_check_run)
  end

  context "with valid new pr token with prefix and checksum" do
    before do
      autofix_suggestion_job
      allow(Dependabot::Exceptions).to receive(:push)
    end

    it { is_expected.to call_next_middleware }
    it { is_expected.to provide(token: pr_token) }
    it { is_expected.to provide(autofix_job: autofix_suggestion_job) }

    it "adds PullRequest information to the error tracker context" do
      instance.call

      expect(Dependabot::Exceptions).
        to have_received(:push).
        with(a_hash_including(
               "gh.dependabot_api.pull_request.id": pull_request.id,
             ))
    end

    it "records stage success" do
      expect(autofix_suggestion_job).to receive(:observe_stage).
        with(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE).
        and_call_original

      expect(AutofixSuggestionJob::Stages).to receive(:record_success).
        with(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE)

      instance.call
    end
  end

  context "with invalid token" do
    let(:received_token) { "invalid-token" }

    it { is_expected.to respond_with_status(403) }

    it "records a stage failure" do
      expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)
      expect(AutofixSuggestionJob::Stages).to receive(:record_error).
        with(hash_including(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE))
      instance.call
    end

    it "marks the autofix job's check run as failued" do
      instance.call
      expect(autofix_suggestion_job).to have_received(:complete_github_check_run).with(
        conclusion: GitHub::CheckRun::Conclusion::FAILURE
      )
    end
  end

  context "with no token" do
    let(:received_token) { nil }

    it { is_expected.to respond_with_status(401) }

    it "records a stage failure" do
      expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)
      expect(AutofixSuggestionJob::Stages).to receive(:record_error).
        with(hash_including(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE))
      instance.call
    end

    it "marks the autofix job's check run as failued" do
      instance.call
      expect(autofix_suggestion_job).to have_received(:complete_github_check_run).with(
        conclusion: GitHub::CheckRun::Conclusion::FAILURE
      )
    end
  end

  context "with a bad autofix job id" do
    let(:params) { { id: autofix_suggestion_job_id + 1 } }

    it { is_expected.to respond_with_status(404) }

    it "records a stage failure" do
      expect(AutofixSuggestionJob::Stages).not_to receive(:record_success)
      expect(AutofixSuggestionJob::Stages).to receive(:record_error).
        with(hash_including(stage: AutofixSuggestionJob::Stages::VALIDATE_DYNAMIC_WORKFLOW_RESPONSE))
      instance.call
    end
  end
end
