# frozen_string_literal: true

require "rails_helper"

RSpec.describe Middlewares::CheckUpdateJobToken do
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
  let(:headers) { { "Authorization" => received_token } }
  let(:params) { { id: job_id } }

  let(:job_token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_job_token) { Base64.strict_encode64(job_token) }
  let(:hashed_job_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(job_token)) }
  let(:job_token_checksum) { Base62.encode(Zlib.crc32(base64_job_token)).rjust(6, Base62::PRIMITIVES[0]) }
  let(:external_job_token) do
    UpdateJob::DEPENDABOT_JOB_TOKEN_PREFIX +
      base64_job_token +
      job_token_checksum
  end
  let(:cred_token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
  let(:base64_cred_token) { Base64.strict_encode64(cred_token) }
  let(:hashed_cred_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(cred_token)) }
  let(:cred_token_checksum) { Base62.encode(Zlib.crc32(base64_cred_token)).rjust(6, Base62::PRIMITIVES[0]) }
  let(:external_cred_token) do
    UpdateJob::DEPENDABOT_CRED_TOKEN_PREFIX +
      base64_cred_token +
      cred_token_checksum
  end

  let(:job_id) { 10 }

  let!(:update_job) do
    FactoryBot.create(
      :update_job, :enqueued,
      id: job_id,
      hashed_token: hashed_job_token,
      hashed_credentials_token: hashed_cred_token,
      trigger_type: :manual
    )
  end

  context "with valid new job token with prefix and checksum" do
    let(:received_token) { external_job_token }

    it { is_expected.to call_next_middleware }
    it { is_expected.to provide(token: job_token) }
    it { is_expected.to provide(update_job: update_job) }

    it "adds UpdateJob information to the error tracker context" do
      allow(Dependabot::Exceptions).to receive(:push)

      instance.call

      expect(Dependabot::Exceptions).
        to have_received(:push).
        with(a_hash_including(
               "gh.repo.id": update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": update_job.id,
               "gh.dependabot_api.update_config.id": update_job.update_config.id,
               "gh.owner.id": update_job.update_config.account.github_id,
               "gh.dependabot_api.update_config.package_manager": "bundler",
               "gh.dependabot_api.update_job.trigger_type": "manual",
             ))
    end

    context "that doesn't match the passed job ID" do
      before { FactoryBot.create(:update_job, id: 2) }

      let(:params) { { id: 2 } }

      it { is_expected.to respond_with_status(403) }
    end

    context "when a credentials token is required" do
      let(:config) { { type: :credentials } }

      it { is_expected.to respond_with_status(403) }
    end
  end

  context "with valid old job token with no prefix and checksum" do
    let(:job_token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
    let(:hashed_job_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(job_token)) }
    let(:base64_job_token) { Base64.strict_encode64(job_token) }
    let(:received_token) { base64_job_token }

    it { is_expected.to call_next_middleware }
    it { is_expected.to provide(token: job_token) }
    it { is_expected.to provide(update_job: update_job) }

    it "adds UpdateJob information to the error tracker context" do
      allow(Dependabot::Exceptions).to receive(:push)

      instance.call

      expect(Dependabot::Exceptions).
        to have_received(:push).with(a_hash_including(
                                       "gh.repo.id": update_job.repo.github_id,
                                       "gh.dependabot_api.update_job.id": update_job.id,
                                       "gh.dependabot_api.update_config.id": update_job.update_config.id,
                                       "gh.owner.id": update_job.update_config.account.github_id,
                                       "gh.dependabot_api.update_config.package_manager": "bundler",
                                       "gh.dependabot_api.update_job.trigger_type": "manual",
                                     ))
    end

    context "that doesn't match the passed job ID" do
      before { FactoryBot.create(:update_job, id: 2) }

      let(:params) { { id: 2 } }

      it { is_expected.to respond_with_status(403) }
    end

    context "when a credentials token is required" do
      let(:config) { { type: :credentials } }

      it { is_expected.to respond_with_status(403) }
    end
  end

  context "with valid new credentials token with prefix and checksum" do
    let(:config) { { type: :credentials } }
    let(:received_token) { external_cred_token }

    it { is_expected.to call_next_middleware }
    it { is_expected.to provide(token: cred_token) }
    it { is_expected.to provide(update_job: update_job) }

    context "that doesn't match the passed job ID" do
      before { FactoryBot.create(:update_job, id: 2) }

      let(:params) { { id: 2 } }

      it { is_expected.to respond_with_status(403) }
    end

    context "when a job token is required" do
      let(:config) { {} }

      it { is_expected.to respond_with_status(403) }
    end
  end

  context "with valid old credentials token with no prefix and checksum" do
    let(:cred_token) { RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes) }
    let(:base64_cred_token) { Base64.strict_encode64(cred_token) }
    let(:hashed_cred_token) { Base64.strict_encode64(RbNaCl::Hash.sha256(cred_token)) }
    let(:config) { { type: :credentials } }
    let(:received_token) { base64_cred_token }

    it { is_expected.to call_next_middleware }
    it { is_expected.to provide(token: cred_token) }
    it { is_expected.to provide(update_job: update_job) }

    context "that doesn't match the passed job ID" do
      before { FactoryBot.create(:update_job, id: 2) }

      let(:params) { { id: 2 } }

      it { is_expected.to respond_with_status(403) }
    end

    context "when a job token is required" do
      let(:config) { {} }

      it { is_expected.to respond_with_status(403) }
    end
  end

  context "with invalid token" do
    let(:received_token) { "invalid-token" }

    it { is_expected.to respond_with_status(403) }
  end

  context "with no token" do
    let(:received_token) { nil }

    it { is_expected.to respond_with_status(401) }
  end
end
