# frozen_string_literal: true

require "rails_helper"

RSpec.describe Stafftools::ResyncAccountJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:installation_id) { 25222 }

  let!(:repo1) do
    FactoryBot.create(:repo, account: account)
  end

  let!(:repo2) do
    FactoryBot.create(:repo, account: account)
  end

  let(:job) do
    described_class.new(
      account: account,
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }

  let(:github_installation) { fixture("github_responses/installation.json") }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }

  shared_context "with an installation in GitHub" do
    before do
      stub_request(:get, "#{github_url}organizations/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(:get, "#{github_url}app/installations/#{installation_id}").
        to_return(status: 200, body: "{}", headers: json_header)
    end
  end

  shared_context "with no installation in GitHub" do
    before do
      stub_request(:get, "#{github_url}organizations/#{account.github_id}/installation").
        to_return(status: 404)
    end
  end

  context "when the account is inactive" do
    let(:account) do
      FactoryBot.create(
        :account, :inactive, :dependabot,
        installation_id: installation_id,
      )
    end

    it "is inactive" do
      expect(account).not_to be_active
    end

    context "and there is an active install in GitHub" do
      include_context "with an installation in GitHub"

      it "activates the account" do
        expect { job.perform_now }.to change { account.reload.active? }.from(false).to(true)
      end

      it "enqueues a job to resync the account's repos" do
        job.perform_now

        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repo1.github_id)
        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repo2.github_id)
      end
    end

    context "and there is no active install in GitHub" do
      include_context "with no installation in GitHub"

      it "does not activate the account" do
        expect { job.perform_now }.not_to change { account.reload.active? }.from(false)
      end

      it "does not attempt to resync any repos" do
        expect { job.perform_now }.not_to have_enqueued_job(Stafftools::ResyncRepoJob)
      end
    end
  end

  context "when the account is active" do
    let(:account) do
      FactoryBot.create(
        :account, :active, :dependabot,
        installation_id: installation_id,
      )
    end

    it "is active" do
      expect(account).to be_active
    end

    context "and there is an active install in GitHub" do
      include_context "with an installation in GitHub"

      it "enqueues a job to resync the account's repos" do
        job.perform_now

        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repo1.github_id)
        expect(Stafftools::ResyncRepoJob).to have_been_enqueued.with(account: account, github_id: repo2.github_id)
      end
    end

    context "and there is no active install in GitHub" do
      include_context "with no installation in GitHub"

      it "deactivates the account" do
        expect { job.perform_now }.to change { account.reload.active? }.from(true).to(false)
      end
    end
  end
end
