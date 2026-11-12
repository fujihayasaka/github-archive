# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  let(:repo) do
    FactoryBot.create(:repo, :bump_test)
  end

  let(:user) { "user" }
  let(:channel) { "#dependabot-ops" }
  let(:repo_nwo) { repo.full_name }

  describe "repo pause" do
    subject(:run_chatop) do
      chat "dependabot repo pause #{repo_nwo}",
           user,
           channel
    end

    it "enqueues an PauseRepoJob" do
      expect { run_chatop }.to have_enqueued_job(PauseRepoJob).with(repo_id: repo.id, event_source: "chatops")
    end

    context "with an repo that doesn't exist" do
      let(:repo_nwo) { "dependabot/sinatra" }

      before { FactoryBot.create(:account, github_login: "dependabot") }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end
  end

  describe "repo unpause" do
    subject(:run_chatop) do
      chat "dependabot repo unpause #{repo_nwo}",
           user,
           channel
    end

    before { repo.update!(paused_at: 1.minute.ago) }

    it "unpauses the repository" do
      expect { run_chatop }.to change { repo.reload.paused? }.from(true).to(false)
    end

    it "enqueues an AfterUnpauseRepoJob" do
      expect { run_chatop }.to have_enqueued_job(AfterUnpauseRepoJob).with(repo_id: repo.id)
    end

    context "with an repo that doesn't exist" do
      let(:repo_nwo) { "dependabot/sinatra" }

      before { FactoryBot.create(:account, github_login: "dependabot") }

      it "returns an error" do
        run_chatop

        expect(chatop_error).to include(
          "Repository `#{repo_nwo}` not found."
        )
      end
    end
  end
end
