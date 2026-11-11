# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyGitHubOfSuccessJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(update_job: update_job, pull_request: pull_request)
  end

  let(:pull_request) do
    FactoryBot.create(:pull_request)
  end

  let(:update_job) do
    FactoryBot.create(:update_job, :processing,
                      update_config: pull_request.update_config)
  end

  context "when the repo is no longer accessible to the installation" do
    it "does not retry the job" do
      expect(MarkGitHubJobComplete).to receive(:new).
        with(update_job: update_job, pull_request: pull_request).
        and_raise(GitHubGraphQL::UnauthorizedError)

      expect(job.perform_now).to be_truthy
    end
  end
end
