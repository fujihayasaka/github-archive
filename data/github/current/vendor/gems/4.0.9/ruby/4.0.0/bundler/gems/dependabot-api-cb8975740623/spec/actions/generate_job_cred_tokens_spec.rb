# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateJobCredTokens do
  let(:generate_job_cred_token) { described_class.new }

  describe "#run" do
    it "returns a hash with external_job_token and external_cred_token keys" do
      expect(generate_job_cred_token.run.keys).to match_array(%i(external_job_token external_cred_token))
    end

    it "returns a hash with job_token and hashed_token keys for external_job_token" do
      expect(generate_job_cred_token.run[:external_job_token].keys).to match_array(%i(job_token hashed_token))
    end

    it "returns a hash with cred_token and hashed_token keys for external_cred_token" do
      expect(generate_job_cred_token.run[:external_cred_token].keys).to match_array(%i(cred_token hashed_token))
    end
  end

  describe "#generate_job_token" do
    let(:job_token) { generate_job_cred_token.generate_job_token }

    it "returns a hash with job_token and hashed_token keys" do
      expect(job_token.keys).to match_array(%i(job_token hashed_token))
    end

    it "returns a job_token with the correct prefix" do
      expect(job_token[:job_token]).to start_with(UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX)
    end

    it "validate the job token checksum" do
      expect(valid_checksum?(job_token[:job_token])).to be true
    end
  end

  describe "#generate_cred_token" do
    let(:cred_token) { generate_job_cred_token.generate_cred_token }

    it "returns a hash with cred_token and hashed_token keys" do
      expect(cred_token.keys).to match_array(%i(cred_token hashed_token))
    end

    it "returns a cred_token with the correct prefix" do
      expect(cred_token[:cred_token]).to start_with(UpdateJob::DEPENDABOT_CRED_TOKEN_PREFIX)
    end

    it "validate the cred token checksum" do
      expect(valid_checksum?(cred_token[:cred_token])).to be true
    end
  end

  describe "#generate_autofix_token" do
    let(:pull_request_token) { generate_job_cred_token.generate_autofix_token }

    it "returns a hash with job_token and hashed_token keys" do
      expect(pull_request_token.keys).to match_array(%i(pr_token hashed_token))
    end

    it "returns a job_token with the correct prefix" do
      expect(pull_request_token[:pr_token]).to start_with(PullRequest::DEPENDABOT_PR_TOKEN_PREFIX)
    end

    it "validate the job token checksum" do
      expect(valid_checksum?(pull_request_token[:pr_token])).to be true
    end
  end
end
