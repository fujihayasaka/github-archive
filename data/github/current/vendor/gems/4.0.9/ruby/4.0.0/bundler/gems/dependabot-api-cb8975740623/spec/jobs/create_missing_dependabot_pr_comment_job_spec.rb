# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateMissingDependabotPrCommentJob do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      repo: repo, github_number: 122, comment_url: "http://example.com",
      pr_closed_at: closed_at, pr_created_at: created_at
    )
  end

  let(:repo) { create(:repo) }
  let(:created_at) { 2.days.ago }
  let(:closed_at) { 3.years.ago }

  let(:dummy_comment_creator) do
    instance_double(CreateMissingDependabotPrComment, run: nil)
  end

  it "delegates to the CreateMissingDependabotPrComment action" do
    allow(CreateMissingDependabotPrComment).
      to receive(:new).
      and_return(dummy_comment_creator)
    expect(dummy_comment_creator).to receive(:run)

    job.perform_now

    expect(CreateMissingDependabotPrComment).to have_received(:new).with(
      repo: repo,
      github_number: 122,
      comment_url: "http://example.com",
      pr_closed_at: closed_at,
      pr_created_at: created_at
    )
  end
end
