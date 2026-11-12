# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::EnqueueRepoCiChecks, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  let!(:repo) { FactoryBot.create(:repo) }

  it "enqueues a CheckRepoHasCi job for each repo" do
    expect { job.perform_now }.
      to have_enqueued_job(CheckRepoHasCiJob).
      with(repo: repo)
  end

  context "when the repository is paused", feature: :inactivity_pausing do
    before do
      repo.update!(paused_at: 1.minute.ago)
    end

    it "does not enqueue any CheckRepoHasCi jobs" do
      expect { job.perform_now }.
        not_to have_enqueued_job(CheckRepoHasCiJob)
    end
  end
end
