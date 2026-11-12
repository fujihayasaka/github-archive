# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeactivateRepoJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(account: repo.account, repo_github_id: repo.github_id, user: user)
  end

  let(:user) { { "login" => "octocat", "id" => 1 } }
  let(:repo) { FactoryBot.create(:repo) }

  let(:dummy_deactivater) do
    instance_double(DeactivateRepo, run: nil)
  end

  it "delegates to the DeactivateRepoaction" do
    expect(DeactivateRepo).
      to receive(:new).
      with(
        account: repo.account,
        repo_github_id: repo.github_id,
        user: user
      ).
      and_return(dummy_deactivater)
    expect(dummy_deactivater).to receive(:run)

    job.perform_now
  end

  it "delegates to the DeactivateRepoaction with nil account" do
    expect(DeactivateRepo).
      to receive(:new).
      with(
        account: nil,
        repo_github_id: repo.github_id,
        user: user
      ).
      and_return(dummy_deactivater)
    expect(dummy_deactivater).to receive(:run)

    described_class.new(repo_github_id: repo.github_id, user: user).perform_now
  end
end
