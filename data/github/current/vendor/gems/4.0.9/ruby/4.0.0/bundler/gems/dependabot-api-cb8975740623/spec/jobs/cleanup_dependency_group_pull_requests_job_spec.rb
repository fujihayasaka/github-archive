# frozen_string_literal: true

require "rails_helper"

RSpec.describe CleanupDependencyGroupPullRequestsJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(dependency_group.id)
  end

  context "with an active DependencyGroup" do
    let(:dependency_group) do
      FactoryBot.create(:dependency_group, :active)
    end

    before do
      FactoryBot.create(:pull_request,
                        :up_to_date,
                        dependency_group: dependency_group,
                        grouped_update: true)
    end

    it "does not attempt to close any pull requests" do
      expect { job.perform_now }.not_to have_enqueued_job(ClosePullRequestJob)
    end
  end

  context "with a deleted DependencyGroup" do
    let(:dependency_group) do
      FactoryBot.create(:dependency_group, :deleted)
    end

    let!(:open_pull_request) do
      FactoryBot.create(:pull_request,
                        :up_to_date,
                        dependency_group: dependency_group,
                        grouped_update: true)
    end

    let!(:merged_pull_request) do
      FactoryBot.create(:pull_request,
                        :merged,
                        dependency_group: dependency_group,
                        grouped_update: true)
    end

    let!(:closed_pull_request) do
      FactoryBot.create(:pull_request,
                        :closed,
                        dependency_group: dependency_group,
                        grouped_update: true)
    end

    it "enqueues jobs to close any open pull requests" do
      job.perform_now

      expect(ClosePullRequestJob).
        to have_been_enqueued.with(pull_request: open_pull_request, reason: "dependency_group_deleted")

      expect(ClosePullRequestJob).
        not_to have_been_enqueued.with(pull_request: merged_pull_request, reason: nil, comment_on_pr: false)

      expect(ClosePullRequestJob).
        not_to have_been_enqueued.with(pull_request: closed_pull_request, reason: nil, comment_on_pr: false)
    end
  end
end
