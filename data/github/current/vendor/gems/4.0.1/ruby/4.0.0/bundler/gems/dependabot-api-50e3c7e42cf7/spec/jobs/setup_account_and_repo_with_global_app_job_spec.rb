# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetupAccountAndRepoWithGlobalAppJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      account_github_id: 12345,
      repo_github_id: 88632334,
      tenant_id: tenant_id,
      tenant_slug: tenant_slug,
      event_source: "test",
      sha: "sha",
    )
  end

  let(:tenant_id) { Dependabot.proxima? ? "1234" : nil }
  let(:tenant_slug) { Dependabot.proxima? ? "lugman-inc" : nil }

  let(:github_url) { "https://internal-api.service.iad.github.net" }
  let(:json_header) { { "Content-Type" => "application/json" } }

  let(:global_access_token_url) do
    "#{github_url}/app/global/access_tokens"
  end

  let(:user_url) do
    "#{github_url}/user/12345"
  end

  before do
    # Clear out cached access tokens
    Rails.cache.clear
  end

  context "with a new accessible account" do
    before do
      stub_request(:post, global_access_token_url).
        with(body: { target_id: 12345 }.to_json).
        to_return(
          status: 200,
          body: erb_fixture("github_responses/global_access_token.json"),
          headers: json_header,
        )
      stub_request(:get, user_url).
        to_return(status: 200, body: fixture("github_responses/user_by_id.json"), headers: json_header)
    end

    it "creates the account" do
      expect { job.perform_now }.to change(Account, :count).by(1)
    end

    it "enqueues the repo setup" do
      expect { job.perform_now }.
        to have_enqueued_job(SetupRepoJob).
        with do |args|
          expect(args[:account].github_id).to eq(12345)
          expect(args[:github_id]).to eq(88632334)
          expect(args[:sha]).to eq("sha")
        end
    end
  end

  context "when there's a retryable error" do
    before do
      stub_request(:post, global_access_token_url).
        to_return(
          status: 500,
          body: fixture("github_responses/error_generic.json"),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "does not create a new Account object" do
      expect { job.perform_now }.not_to change(Account, :count)
    end

    it "retries the job" do
      expect { job.perform_now }.
        to have_enqueued_job(described_class)
    end
  end

  context "when there's a retryable error that does not resolve" do
    before do
      allow(Failbot).to receive(:report)
      stub_request(:post, global_access_token_url).
        to_return(
          status: 500,
          body: fixture("github_responses/error_generic.json"),
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "raises" do
      perform_enqueued_jobs do
        expect do
          job.perform_now
        end.to raise_error(Octokit::InternalServerError)
      end
    end
  end
end
