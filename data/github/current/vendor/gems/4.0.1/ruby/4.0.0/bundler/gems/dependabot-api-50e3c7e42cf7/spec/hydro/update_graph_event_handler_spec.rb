# frozen_string_literal: true

require "rails_helper"
require "json"
require "ecosystems"

RSpec.describe UpdateGraphEventHandler do
  let(:fixture_name) { "update_graph" }

  let(:hydro_payload) do
    hydro_fixture(
      name: fixture_name,
      schema: "dependency_graph.v0.UpdateGraphEvent",
    )
  end

  let(:message) do
    instance_double(
      Hydro::Consumer::ConsumerMessage,
      value: hydro_payload,
      timestamp: Time.now.utc,
      headers: { "X-GitHub-Tenant-ID" => "123", "X-GitHub-Tenant" => "github" },
    )
  end

  describe "#run" do
    subject(:run) { described_class.run(message) }

    it "creates a graph update job if the account is active" do
      account = create(:account, :active, github_id: 1)
      create(:repo, account: account, github_id: 1, name: "hello-world")

      expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

      expect(UpdateConfig.count).to eq(1)

      expect(UpdateConfig.last.package_manager).to eq(PackageManagers::GO_MODULES)
      expect(UpdateConfig.last.directories).to eq(["/."])
    end

    it "does not create a graph update job when the account is inactive" do
      account = create(:account, :inactive, github_id: 1)
      create(:repo, account: account, github_id: 1, name: "hello-world")

      expect { run }.not_to have_enqueued_job(CreateGraphUpdateJob)

      expect(UpdateConfig.count).to eq(0)
    end

    context "when several directories are sent for the same ecosystem" do
      let(:fixture_name) { "update_graph_multiple_dirs" }

      it "creates a single graph update job with all directories" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

        expect(Repo.count).to eq(1)
        expect(UpdateConfig.count).to eq(1)

        expect(UpdateConfig.last.package_manager).to eq(PackageManagers::GO_MODULES)
        expect(UpdateConfig.last.directories).to match_array(%w(/foo /bar))
      end
    end

    context "when an unknown ecosystem is sent" do
      let(:fixture_name) { "update_graph_unknown_ecosystem" }

      it "skips the unknown ecosystem and creates a graph update job for the known ones" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect(Dependabot::Logger).to receive(:warn).with(
          hash_including(msg: "Unknown ecosystem in graph change, skipping")
        )

        expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

        expect(Repo.count).to eq(1)
        expect(UpdateConfig.count).to eq(1)

        expect(UpdateConfig.last.package_manager).to eq(PackageManagers::GO_MODULES)
        expect(UpdateConfig.last.directories).to match_array(%w(/bar))
      end
    end

    context "when the repository does not exist" do
      it "enqueues an onboarding job" do
        create(:account, :active, github_id: 1)

        expect { run }.to have_enqueued_job(UpdateGraph::OnboardRepositoryJob).on_queue("graph_onboard_repository")

        expect(Repo.count).to eq(0)
        expect(UpdateConfig.count).to eq(0)
      end

      it "records the onboarding metric" do
        create(:account, :active, github_id: 1)

        expect(MetricsClient).to receive(:increment).with(
          "consumer.repository_onboarded",
          tags: { trigger: "dependency_graph" }
        )

        run
      end

      it "does not create a graph update job directly" do
        create(:account, :active, github_id: 1)

        expect { run }.not_to have_enqueued_job(CreateGraphUpdateJob)
      end
    end
  end
end
