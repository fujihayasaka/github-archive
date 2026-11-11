# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20191213191241_timeout_jobs_stuck_enqueued.rb"
RSpec.describe "TimeoutJobsStuckEnqueued" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:old_stuck_job) do
    FactoryBot.create(:update_job).tap do |job|
      travel_to "2019-11-12 23:59:59 UTC" do
        job.transition_to!(:enqueued)
      end
    end
  end
  let(:transition) do
    Dependabot::Transitions::TimeoutJobsStuckEnqueued.new(dry_run: false)
  end
  let(:dry_run_transition) do
    Dependabot::Transitions::TimeoutJobsStuckEnqueued.new
  end

  let!(:first_stuck_job) do
    FactoryBot.create(:update_job).tap do |job|
      travel_to("2019-11-13 00:00:00 UTC") do
        job.transition_to!(:enqueued)
      end
    end
  end

  let!(:last_stuck_job) do
    FactoryBot.create(:update_job).tap do |job|
      travel_to("2019-12-13 00:00:00 UTC") do
        job.transition_to!(:enqueued)
      end
    end
  end

  let!(:uninvolved_stuck_job) do
    FactoryBot.create(:update_job).tap do |job|
      travel_to("2019-12-13 00:00:01 UTC") do
        job.transition_to!(:enqueued)
      end
    end
  end

  let!(:valid_enqueued_job) do
    FactoryBot.create(:update_job).tap do |job|
      job.transition_to!(:enqueued)
    end
  end

  before do
    expect(old_stuck_job.current_state).to eql("enqueued")
    expect(first_stuck_job.current_state).to eql("enqueued")
    expect(last_stuck_job.current_state).to eql("enqueued")
    expect(uninvolved_stuck_job.current_state).to eql("enqueued")
    expect(valid_enqueued_job.current_state).to eql("enqueued")
  end

  context "write" do
    it "performs the transition" do
      transition.perform

      expect(UpdateJob.find(old_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(first_stuck_job.id).current_state).
        to eql("timed_out")
      expect(UpdateJob.find(last_stuck_job.id).current_state).
        to eql("timed_out")
      expect(UpdateJob.find(uninvolved_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(valid_enqueued_job.id).current_state).
        to eql("enqueued")
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      dry_run_transition.perform

      expect(UpdateJob.find(old_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(first_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(last_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(uninvolved_stuck_job.id).current_state).
        to eql("enqueued")
      expect(UpdateJob.find(valid_enqueued_job.id).current_state).
        to eql("enqueued")
    end
  end
end
