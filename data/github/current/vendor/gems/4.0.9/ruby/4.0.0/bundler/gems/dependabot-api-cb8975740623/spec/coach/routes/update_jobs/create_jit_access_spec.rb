# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::CreateJitAccess do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:account) { create(:account, :dependabot, :active) }
  let(:repo) { create(:repo, :bump_test, account:) }
  let(:other_repo) { create(:repo, name: "another-repo", account:) }
  let(:update_job) { create(:update_job, :processing, repo:) }
  let(:update_config) { update_job.update_config }
  let(:params) do
    { account: account.github_login, repository: other_repo.name }
  end
  let(:new_token) { "new-token" }
  let(:tokens_service) { instance_double(GitHub::Twirp::Tokens) }
  let(:redis) { Dependabot.redis }

  before do
    redis.flushdb
    allow(GitHub::Twirp::Tokens).to receive(:new).and_return(tokens_service)
    allow(tokens_service).to receive(:create_jit_access).and_return(
      GitHub::Twirp::Tokens::JitAccessResponse.new(token: new_token, repository_id: other_repo.github_id)
    )

    allow(update_config).to receive(:add_jit_accessed_internal_github_repo_ids).and_call_original
    allow(Dependabot::Logger).to receive(:info)
    allow(MetricsClient).to receive(:increment)
  end

  it "returns new credentials on success" do
    expect(instance).to respond_with_body_that_matches({ username: "x-access-token", password: new_token }.to_json)
    expect(tokens_service).to have_received(:create_jit_access).with(
      account_name: update_job.repo.account.github_login,
      repo_name: other_repo.name,
      source_account_name: update_job.repo.account.github_login
    )
    expect(Dependabot::Logger).to have_received(:info).with(
      hash_including(msg: "Requesting JIT access token for update job", success: true)
    )
  end

  it "returns forbidden when the token is not found" do
    allow(tokens_service).to receive(:create_jit_access).and_raise(GitHub::Twirp::Tokens::Error)

    expect(instance).to respond_with_status(403)
    expect(Dependabot::Logger).to have_received(:info).with(
      hash_including(msg: "Requesting JIT access token for update job", success: false)
    )
  end

  it "updates cached repo ids that the config accessed" do
    instance.call

    expect(update_config.jit_accessed_internal_github_repo_ids).to eq([other_repo.github_id])
  end

  context "when the request is cross-org" do
    let(:params) { { account: "another-org", repository: other_repo.name } }

    before do
      create(:account, github_login: "another-org")
    end

    it "returns success" do
      expect(instance).to respond_with_status(200)
    end

    it "increments the cross_org Datadog metric with success tag" do
      instance.call

      expect(MetricsClient).to have_received(:increment).with(
        "dependabot.jit_access.cross_org",
        tags: { success: true }
      )
    end

    it "increments the cross_org Datadog metric with failure tag when token fetch fails" do
      allow(tokens_service).to receive(:create_jit_access).and_raise(GitHub::Twirp::Tokens::Error)

      instance.call

      expect(MetricsClient).to have_received(:increment).with(
        "dependabot.jit_access.cross_org",
        tags: { success: false }
      )
    end
  end

  context "when the request is for the same org but the case differs" do
    let(:params) { { account: account.github_login.upcase, repository: other_repo.name } }

    it "returns new credentials" do
      expect(instance).to respond_with_body_that_matches({ username: "x-access-token", password: new_token }.to_json)
      expect(tokens_service).to have_received(:create_jit_access).with(
        account_name: account.github_login.upcase,
        repo_name: other_repo.name,
        source_account_name: account.github_login
      )
    end
  end
end
