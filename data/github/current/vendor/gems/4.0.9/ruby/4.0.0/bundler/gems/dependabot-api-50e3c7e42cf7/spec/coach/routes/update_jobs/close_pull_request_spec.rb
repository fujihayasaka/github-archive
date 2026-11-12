# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::ClosePullRequest do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) { params_hash.deep_symbolize_keys }
  let(:params_hash) do
    { data: { "dependency-names" => names, "reason" => "dependency_removed" } }
  end
  let(:names) { ["business"] }
  let(:update_config) { FactoryBot.create(:update_config) }

  context "for an enqueued update job" do
    let(:update_job) do
      FactoryBot.create(:update_job, :enqueued, update_config: update_config)
    end

    it { is_expected.to respond_with_status(400) }
  end

  context "for an update job targetting a specific dependency" do
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :updating,
        update_job: old_update_job,
        dependencies: [{ name: "business", version: "1.8.0" }],
        github_number: 47,
      )
    end

    let(:update_job) do
      update_job = pull_request.last_transition.update_job
      update_job.transition_to!(:enqueued)
      update_job.transition_to!(:processing)
      update_job
    end
    let!(:pull_request) do
      FactoryBot.create(
        :pull_request, :updating,
        update_job: old_update_job,
        dependencies: [{ name: "business", version: "1.8.0" }],
        github_number: 47,
      )
    end
    let(:old_update_job) do
      FactoryBot.create(:update_job, update_config: update_config)
    end

    context "that isn't the dependency that has been updated" do
      let(:names) { ["prius"] }

      it { is_expected.to respond_with_status(400) }
    end

    it { is_expected.to respond_with_status(204) }

    it "enqueues a job to close the pull request" do
      expect { instance.call }.to have_enqueued_job(ClosePullRequestJob)
    end
  end
end
