# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledJobs::ReportUpdateJobBacklog, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new }

  before { FactoryBot.create(:update_job, :enqueued) }

  it "doesn't enqueue a bumping job" do
    expect(MetricsClient).to receive(:gauge).with(
      "app_update_job_backlog", 1
    )
    job.perform_now
  end
end
