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
  end
end
