# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleWebhook::Label do
  subject(:action) { described_class.new(webhook_body: webhook_body) }

  context "for an unrelated label" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/label_deleted")
      hash.deep_symbolize_keys
    end

    context "with an active update config" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

      it "does not queue up a UpdateDefaultLabelsJob" do
        expect { action.run }.not_to have_enqueued_job(UpdateDefaultLabelsJob)
      end
    end
  end

  context "for a dependency label" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/label_deleted")
      hash["label"]["name"] = "Dependency"
      hash.deep_symbolize_keys
    end

    context "with an active update config" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

      it "queues up an UpdateDefaultLabelsJob" do
        expect { action.run }.
          to have_enqueued_job(UpdateDefaultLabelsJob).
          with(repo: repo)
      end
    end

    context "without an active update config" do
      let!(:repo) { FactoryBot.create(:repo, :bump_test) }

      it "does not queue up an UpdateDefaultLabelsJob" do
        expect { action.run }.not_to have_enqueued_job(UpdateDefaultLabelsJob)
      end
    end
  end

  context "for a language label" do
    let(:webhook_body) do
      hash = json_fixture("github_webhooks/label_deleted")
      hash["label"]["name"] = "Ruby"
      hash.deep_symbolize_keys
    end

    context "with an active update config" do
      let!(:repo) { FactoryBot.create(:repo, :active, :bump_test) }

      it "queues up an UpdateDefaultLabelsJob" do
        expect { action.run }.
          to have_enqueued_job(UpdateDefaultLabelsJob).
          with(repo: repo)
      end
    end
  end
end
