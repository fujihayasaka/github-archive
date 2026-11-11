# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateGraphUpdateJob do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(update_config:, directories:)
  end

  let(:update_config) { create(:update_config) }
  let(:directories) { ["/"] }

  describe "#perform" do
    it "creates a graph update" do
      expect { job.perform_now }.to change(UpdateJob, :count).by(1)
      expect(UpdateJob.last.directories).to eq(directories)
    end

    it "enqueues a StartUpdateJob job" do
      expect { job.perform_now }.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::GraphLow)
    end

    context "when github_request_id is provided" do
      subject(:job) do
        described_class.new(update_config:, directories:, github_request_id: 42)
      end

      it "persists the github_request_id on the UpdateJob" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)
        expect(UpdateJob.last.github_request_id).to eq(42)
      end
    end

    context "when github_request_id is not provided" do
      it "does not set github_request_id on the UpdateJob" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)
        expect(UpdateJob.last.github_request_id).to be_nil
      end
    end

    context "when base_commit_sha is provided" do
      subject(:job) do
        described_class.new(update_config:, directories:, base_commit_sha: "abc123def456")
      end

      it "persists base_commit_sha on the UpdateJob" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)
        expect(UpdateJob.last.base_commit_sha).to eq("abc123def456")
      end
    end

    context "when base_commit_sha is not provided" do
      it "does not set base_commit_sha on the UpdateJob" do
        expect { job.perform_now }.to change(UpdateJob, :count).by(1)
        expect(UpdateJob.last.base_commit_sha).to be_nil
      end
    end
  end
end
