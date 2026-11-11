# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreateSecurityUpdateJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) do
    described_class.new(
      update_config: update_config,
      dependency_update: dependency_update,
      advisory: advisory,
      dependencies: dependencies,
      feature_flags: feature_flags,
      directories: directories
    )
  end

  let(:directories) { nil }

  let(:feature_flags) { [] }

  let(:hydro_payload) do
    hydro_fixture(
      name: "pip",
      schema: "github.v1.RepositoryVulnerabilityAlertCreate"
    )
  end

  let(:original_message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: hydro_payload,
      timestamp: Time.now.utc,
      headers: { "X-GitHub-Tenant-ID" => "1234" }
    )
  end

  let(:dependency_update) do
    ::HydroHandlers::GitHub::DependencyUpdate.from_message(original_message)
  end

  let(:advisory) do
    ::HydroHandlers::GitHub::SecurityVulnerability.from_message(original_message)
  end

  let(:dependencies) { nil }

  let(:account) do
    create(:account, github_login: "dsp-testing")
  end

  let(:repo) do
    create(:repo, account: account)
  end

  let(:update_config) do
    create(:update_config, :active, :daily, repo: repo)
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for).and_return("top_secret")
  end

  describe "#perform" do
    it "creates an update job" do
      expect { job.perform_now }.to change(UpdateJob, :count).from(0).to(1)
    end

    it "increments metrics" do
      expect(MetricsClient).to receive(:count).
        with("security_update.triggered", 1, tags: hash_including(update_type: "security"))

      job.perform_now
    end

    it "enqueues a PrioritizedJobs::StartUpdateJob" do
      expect { job.perform_now }.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
    end

    context "with the grouped_security_updates flag enabled" do
      let(:feature_flags) { ["grouped_security_updates"] }

      let(:dependencies) { %w(ansible django) }

      it "creates an update job for all vulerable dependencies for that repo" do
        job.perform_now

        expect(UpdateJob.last.dependencies).to match_array(%w(ansible django))
      end
    end

    context "with a security update grouping rule configured" do
      let(:feature_flags) { [] }

      let(:dependencies) { %w(ansible django) }
      let(:update_config) { create(:update_config, :active, :daily, :grouped_security_update, repo: repo) }

      it "creates an update job for all vulerable dependencies for that repo" do
        job.perform_now

        expect(UpdateJob.last.dependencies).to match_array(%w(ansible django))
      end
    end

    context "preventing duplicate jobs" do
      let(:feature_flags) { ["grouped_security_updates"] }
      let(:dependencies) { %w(ansible django) }

      it "noops if a job for the same dependencies is already running" do
        create(:update_job, :security, update_config: update_config, dependencies: dependencies)

        expect { job.perform_now }.not_to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
      end
    end

    context "pending jobs with different dependencies" do
      let(:feature_flags) { ["grouped_security_updates"] }
      let(:dependencies) { %w(ansible django) }

      it "creates an update job for all vulerable dependencies for that repo" do
        create(:update_job, :security, update_config: update_config, dependencies: %w(requests json))

        job.perform_now

        expect(UpdateJob.last.dependencies).to match_array(%w(ansible django))
      end
    end

    context "when directories is passed" do
      let(:directories) { %w(/path/to/dir1 /path/to/dir2) }

      it "creates an update job with the directories" do
        job.perform_now

        expect(UpdateJob.last.directories).to match_array(%w(/path/to/dir1 /path/to/dir2))
      end
    end
  end
end
