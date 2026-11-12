# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewUpdateConfigRateLimit, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(update_job: update_job) }

  let(:update_config) { FactoryBot.create(:update_config, uc_state) }
  let(:uc_state) { :rate_limited }
  let(:repo) { update_config.repo }
  let(:update_job) do
    FactoryBot.create(:update_job, uj_state, update_config: update_config)
  end
  let(:uj_state) { :processed }
  let(:number_of_prs) { 1 }

  before do
    FactoryBot.create_list(
      :pull_request, number_of_prs, update_job: update_job, repo: repo,
    )
  end

  it "transitions the update_config to active" do
    expect { job.perform_now }.
      to change { update_config.reload.current_state }.
      from("rate_limited").to("active")
  end

  context "when the update job has errors" do
    let(:uj_state) { :processed_with_errors }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when five PRs were created" do
    let(:number_of_prs) { 5 }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when no PRs were created" do
    let(:number_of_prs) { 0 }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when the update config is already active" do
    let(:uc_state) { :active }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when the update job targeted a dependency" do
    before { update_job.update!(dependencies: ["rails"]) }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when there is still a pending pull request" do
    before { FactoryBot.create(:pending_pull_request, update_job: update_job) }

    it "does not transition the update_config" do
      expect { job.perform_now }.
        not_to change { update_config.reload.current_state }
    end
  end
end
