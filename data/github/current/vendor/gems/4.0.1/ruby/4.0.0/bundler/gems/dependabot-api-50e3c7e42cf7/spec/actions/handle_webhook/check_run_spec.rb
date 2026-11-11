# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::CheckRun do
  subject(:action) { described_class.new(webhook_body: webhook_body) }

  let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

  context "with a check_run rerequested" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/check_run_rerequested")
      hash["check_run"]["head_sha"] = "somesha"
      hash["repository"]["id"] = repo.github_id
      hash.deep_symbolize_keys
    end

    it "enqueues a config file validation" do
      expect { action.run }.to have_enqueued_job(ValidateConfigFileJob).with(
        account: repo.account,
        repo_github_id: repo.github_id,
        sha: "somesha",
      )
    end
  end

  context "for an initial check_run" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/check_run_rerequested")
      hash["repository"]["id"] = repo.github_id
      hash["action"] = "created"
      hash.deep_symbolize_keys
    end

    # Check-runs are initially created via hydro when a config file change is
    # detected, so we ignore these hooks.
    it "is ignored" do
      expect { action.run }.not_to have_enqueued_job(ValidateConfigFileJob)
    end
  end

  context "when the repo cannot be found" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/check_run_rerequested")
      hash["repository"]["id"] = 1337
      hash.deep_symbolize_keys
    end

    it "is ignored" do
      expect { action.run }.not_to have_enqueued_job(ValidateConfigFileJob)
    end
  end
end
