# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositoriesService::V1::Handler do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:service) do
    DependabotApi::V1::RepositoriesService.new(described_class.new)
  end

  describe "unpause" do
    subject(:rpc_call) do
      service.call_rpc(:Unpause, repository_github_id: repo_github_id, reason: reason)
    end

    let(:repo_github_id) { 42 }
    let(:reason) { "alert-rules-activity" }

    context "when the repo does not exist" do
      let(:repo) { nil }

      it "returns a not found error" do
        response = rpc_call
        expect(response).to be_a(Twirp::Error)
        expect(response.code).to be(:not_found)
      end
    end

    context "when the repo is paused" do
      let!(:repo) do
        FactoryBot.create(:repo, :currently_paused, github_id: repo_github_id)
      end

      it "unpauses the repo" do
        expect { rpc_call }.to change { repo.reload.paused_at }.to(nil)
      end

      it "returns an empty message" do
        expect(rpc_call).to be_a(DependabotApi::V1::UnpauseRepositoryResponse)
      end

      it "logs a marked-as-active event for the repo" do
        logger = stubbed_repo_logger
        expect(logger).
          to receive(:record_event).
          with("marked-as-active", tags: hash_including(triggered_by: reason))

        rpc_call
      end
    end

    context "when the repo is scheduled to be paused" do
      let!(:repo) do
        FactoryBot.create(:repo, :will_pause_later, github_id: repo_github_id)
      end

      it "clears will_pause_at" do
        expect { rpc_call }.to change { repo.reload.will_pause_at }.to(nil)
      end

      it "logs a marked-as-active event for the repo" do
        logger = stubbed_repo_logger
        expect(logger).
          to receive(:record_event).
          with("marked-as-active", tags: hash_including(triggered_by: reason))

        rpc_call
      end
    end

    context "when the repo is not paused" do
      let!(:repo) do
        FactoryBot.create(:repo, :no_pause_planned, github_id: repo_github_id)
      end

      it "is a no-op" do
        expect(repo.paused?).to eq(false)

        logger = stubbed_repo_logger
        expect(logger).not_to receive(:record_event)

        response = rpc_call

        expect(response).to be_a(DependabotApi::V1::UnpauseRepositoryResponse)
      end
    end
  end

  def stubbed_repo_logger
    logger = instance_double(Activity::RepositoryLogger)
    allow(Activity::RepositoryLogger).to receive(:new).and_return(logger)
    logger
  end
end
