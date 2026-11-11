# frozen_string_literal: true

require "rails_helper"

RSpec.describe TransferRepoAccountJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(repo: repo, new_account: new_account) }

  let(:repo) { FactoryBot.create(:repo, :active) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:github_repo_url) { github_url + "repositories/#{repo.github_id}" }
  let(:github_repo) { fixture("github_responses/repo.json") }
  let(:dummy_deactivate_repo) { instance_double(DeactivateRepo, run: nil) }

  before do
    allow(GitHubHelpers).to receive(:access_token_for)
    allow(DeactivateRepo).to receive(:new).
      with(repo_github_id: repo.github_id).
      and_return(dummy_deactivate_repo)
    stub_request(:get, github_repo_url).
      to_return(status: 200, body: github_repo, headers: json_header)
  end

  context "with no new account" do
    let(:new_account) { nil }

    context "when the repo's account has changed" do
      it "deactivates the repo's update configs" do
        job.perform_now
        expect(dummy_deactivate_repo).to have_received(:run)
      end

      context "and the new repo is also in the database" do
        let!(:account) { FactoryBot.create(:account, :dependabot) }

        it "updates the repo's account" do
          expect { job.perform_now }.to change(repo, :account).to(account)
        end
      end
    end

    context "when the repo's account has not changed" do
      let(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

      it "does not deactivate the repo's update configs" do
        job.perform_now
        expect(dummy_deactivate_repo).not_to have_received(:run)
      end
    end

    context "when the repo can't be fetched" do
      before do
        allow(GitHubHelpers).to receive(:access_token_for)
        stub_request(:get, github_repo_url).to_return(status: 404)
      end

      it "does not deactivate the repo's update configs" do
        job.perform_now
        expect(dummy_deactivate_repo).not_to have_received(:run)
      end
    end
  end
end
