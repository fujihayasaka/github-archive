# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestBaseBranchJob, type: :job do
  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }

  let(:dummy_branch_updater) do
    instance_double(UpdatePullRequestBaseBranch, run: nil)
  end

  it "delegates to the UpdatePullRequestBaseBranch action" do
    expect(UpdatePullRequestBaseBranch).
      to receive(:new).
      with(pull_request: pull_request).
      and_return(dummy_branch_updater)
    expect(dummy_branch_updater).to receive(:run)

    job.perform_now
  end
end
