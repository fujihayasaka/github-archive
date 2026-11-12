# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletePullRequestBranchJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }

  let(:dummy_branch_deletor) do
    instance_double(DeletePullRequestBranch, run: nil)
  end

  it "delegates to the DeletePullRequestBranch action" do
    expect(DeletePullRequestBranch).
      to receive(:new).
      with(pull_request: pull_request).
      and_return(dummy_branch_deletor)
    expect(dummy_branch_deletor).to receive(:run)

    job.perform_now
  end
end
