# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::Details do
  include ProximaHelpers

  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request) }

  let(:update_job) { FactoryBot.create(:update_job, :enqueued) }

  before do
    stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")
  end

  context "for an enqueued update job" do
    it { is_expected.to respond_with_status(200) }
    it { is_expected.not_to respond_with_body_that_matches(/"credentials"/) }

    it "updates the job's state to 'processing'" do
      expect { instance.call }.
        to change { update_job.current_state(force_reload: true) }.
        to("processing")
    end

    it "increments a metric" do
      expect(MetricsClient).
        to receive(:count).
        with("update_job.processing", 1, tags: hash_including(runner_type: update_job.runner_type))

      instance.call
    end
  end

  context "for a processing update job" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    it { is_expected.to respond_with_status(200) }
    it { is_expected.not_to respond_with_body_that_matches(/"credentials"/) }

    it "does not update the job's state" do
      expect { instance.call }.
        not_to change { update_job.last_transition(force_reload: true) }
    end
  end

  context "for a processed update job" do
    let(:update_job) { FactoryBot.create(:update_job, :processed) }

    it { is_expected.to respond_with_status(400) }
    it { is_expected.to respond_with_body_that_matches(/been processed/) }
  end

  context "for a job with an invalid registry configuration" do
    let(:update_job) do
      FactoryBot.create(:update_job, :enqueued).tap do |job|
        job.update_config.update_config_registries.create!(registry_name: "non-existent-registry")
      end
    end

    it { is_expected.to respond_with_status(422) }
    it { is_expected.to respond_with_body_that_matches(/"Registry Not Found"/) }

    it "does not include potential registry name PII" do
      expect(instance).not_to respond_with_body_that_matches(/non-existent-registry/)
    end
  end

  context "for a processable update job with experiments" do
    before do
      update_job.repo.enable_feature(:timeout_per_operation)
    end

    it { is_expected.to respond_with_status(200) }

    it "records the experiments" do
      expect { instance.call }.
        to change(update_job, :metrics_metadata).
        to({ "experiments" => { "timeout_per_operation_seconds" => 600 } })
    end
  end

  context "for an update job with experiments and existing metrics" do
    before do
      update_job.repo.enable_feature(:timeout_per_operation)
      update_job.metrics_metadata = { "package_managers" => { "bundler" => "2" } }
    end

    it { is_expected.to respond_with_status(200) }

    it "appends the experiments" do
      expect { instance.call }.
        to change(update_job, :metrics_metadata).
        to({
             "experiments" => { "timeout_per_operation_seconds" => 600 },
             "package_managers" => { "bundler" => "2" },
           })
    end
  end

  context "for an update job with directories in the update_config" do
    let(:update_config) { FactoryBot.create(:update_config, directory: nil, directories: ["/bar", "/foo"]) }
    let(:update_job) { FactoryBot.create(:update_job, :enqueued, update_config: update_config) }

    it { is_expected.to respond_with_status(200) }

    it "includes the directories in the response" do
      expect(instance).to respond_with_body_that_matches(/"directories"/)
    end
  end
end
