# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateVersionSkipCommentJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pull_request: pull_request) }

  let(:pull_request) { FactoryBot.create(:pull_request) }

  let(:dummy_comment_creator) do
    instance_double(CreateVersionSkipComment, run: nil)
  end

  it "delegates to the CreateVersionSkipComment action" do
    expect(CreateVersionSkipComment).
      to receive(:new).
      with(pull_request: pull_request).
      and_return(dummy_comment_creator)
    expect(dummy_comment_creator).to receive(:run)

    job.perform_now
  end
end
