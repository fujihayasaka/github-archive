# frozen_string_literal: true

require "rails_helper"
require "json"
require "cgi"
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

      expect { run }.to have_enqueued_job(CreateGraphUpdateJob).with(
        hash_including(github_request_id: 42)
      )

      expect(UpdateConfig.count).to eq(1)

      expect(UpdateConfig.last.package_manager).to eq(PackageManagers::GO_MODULES)
      expect(UpdateConfig.last.directories).to eq(["/."])
    end

    context "when event_id is missing" do
      let(:fixture_name) { "update_graph_no_event_id" }

      it "creates a graph update job without github_request_id" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")
        expect { run }.to have_enqueued_job(CreateGraphUpdateJob).with(
          hash_including(github_request_id: nil)
        )
      end
    end

    context "when event_id is zero" do
      let(:fixture_name) { "update_graph_zero_event_id" }

      it "creates a graph update job without github_request_id" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")
        expect { run }.to have_enqueued_job(CreateGraphUpdateJob).with(
          hash_including(github_request_id: nil)
        )
      end
    end

    context "when commit_oid is present in the graph change" do
      let(:hydro_payload) do
        super().merge(
          graph_changes: [
            {
              ecosystem: "ECOSYSTEM_GO",
              directory: ".",
              ref_name: "feature-branch",
              commit_oid: "abc123def456",
            },
          ]
        )
      end

      it "creates the ephemeral UpdateConfig with target_branch set from ref_name" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to eq("feature-branch")
      end
    end

    context "when ref_name is empty in the graph change" do
      let(:hydro_payload) do
        super().merge(
          graph_changes: [
            {
              ecosystem: "ECOSYSTEM_GO",
              directory: ".",
              ref_name: "",
              commit_oid: "abc123def456",
            },
          ]
        )
      end

      it "normalises the empty string to nil and creates the ephemeral config with target_branch=nil" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to be_nil
      end
    end

    context "when ref_name is fully qualified (refs/heads/<branch>)" do
      let(:hydro_payload) do
        super().merge(
          graph_changes: [
            {
              ecosystem: "ECOSYSTEM_GO",
              directory: ".",
              ref_name: "refs/heads/feature-branch",
              commit_oid: "abc123def456",
            },
          ]
        )
      end

      it "stores the bare branch name as target_branch" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to eq("feature-branch")
      end
    end

    context "when ref_name is a non-branch ref (e.g. refs/pull/*, refs/tags/*)" do
      let(:hydro_payload) do
        super().merge(
          graph_changes: [
            {
              ecosystem: "ECOSYSTEM_GO",
              directory: ".",
              ref_name: "refs/pull/42/head",
              commit_oid: "abc123def456",
            },
          ]
        )
      end

      it "falls back to nil so the job runs against the repo default branch" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to be_nil
      end
    end

    context "when the branch name itself starts with refs/" do
      let(:hydro_payload) do
        super().merge(
          graph_changes: [
            {
              ecosystem: "ECOSYSTEM_GO",
              directory: ".",
              ref_name: "refs/heads/refs/foo",
              commit_oid: "abc123def456",
            },
          ]
        )
      end

      it "only strips the leading refs/heads/ and keeps the rest verbatim" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to change(UpdateConfig, :count).by(1)
        expect(UpdateConfig.last.target_branch).to eq("refs/foo")
      end
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

        # Verify that we are relaying the event_id through the onboarding path
        expect { run }.to have_enqueued_job(UpdateGraph::OnboardRepositoryJob).on_queue("graph_onboard_repository").with(
          hash_including(event_id: 42)
        )

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

    context "when ECOSYSTEM_PYPI is received" do
      let(:fixture_name) { "update_graph_pypi" }
      let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
      let(:repo_id) { 1 }
      let(:commit_oid) { "abc123" }
      let(:ref_name) { "refs/heads/main" }

      let(:uv_lock_url) { %r{repositories/#{repo_id}/contents/uv\.lock\?ref=} }

      before do
        Rails.cache.clear
        allow(GitHubHelpers).to receive(:access_token_for).and_return("token")
      end

      context "when uv.lock exists" do
        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 200,
            body: { content: Base64.encode64("lockfile content") }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "creates a uv update config" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

          expect(UpdateConfig.count).to eq(1)
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::UV)
        end
      end

      context "when uv.lock does not exist (404)" do
        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 404,
            body: { message: "Not Found" }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "falls back to pip" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

          expect(UpdateConfig.count).to eq(1)
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::PIP)
        end
      end

      context "when the uv.lock API call fails with an error" do
        before do
          stub_request(:get, uv_lock_url).to_return(status: 500)
        end

        it "falls back to pip" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

          expect(UpdateConfig.count).to eq(1)
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::PIP)
        end

        it "logs a warning" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          expect(Dependabot::Logger).to receive(:warn).with(
            hash_including(msg: "Failed to check for uv.lock")
          )

          run
        end
      end

      context "when uv.lock is found in a subdirectory" do
        let(:fixture_name) { "update_graph_pypi_subdir" }
        let(:uv_lock_url) { %r{repositories/#{repo_id}/contents/packages/backend/uv\.lock\?ref=} }

        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 200,
            body: { content: Base64.encode64("lockfile content") }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "creates a uv update config for the subdirectory" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

          expect(UpdateConfig.count).to eq(1)
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::UV)
        end
      end

      context "when the cache is populated from a prior call" do
        before do
          stub_request(:get, uv_lock_url).to_return(
            status: 200,
            body: { content: Base64.encode64("lockfile content") }.to_json,
            headers: { "Content-Type" => "application/json" }
          )
        end

        it "does not make a second API call on repeated runs" do
          create(:account, :active, github_id: 1)
          create(:repo, account: Account.last, github_id: repo_id, name: "hello-world")

          run # first call - populates cache

          WebMock.reset!

          # second call - should use cache without hitting the API
          described_class.run(message)
          expect(WebMock).not_to have_requested(:get, uv_lock_url)
        end
      end
    end

    context "when ECOSYSTEM_NUGET is received" do
      let(:fixture_name) { "update_graph_nuget" }

      it "creates a nuget update config" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

        expect(UpdateConfig.count).to eq(1)
        expect(UpdateConfig.last.package_manager).to eq(PackageManagers::NUGET)
        expect(UpdateConfig.last.directories).to eq(["/."])
      end

      it "is unaffected by uv.lock disambiguation" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect(EcosystemFileDetector).not_to receive(:uv_lock_exists?)

        expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

        expect(UpdateConfig.last.package_manager).to eq(PackageManagers::NUGET)
      end
    end

    context "when a non-PYPI ecosystem is received" do
      it "is unaffected by uv.lock disambiguation" do
        account = create(:account, :active, github_id: 1)
        create(:repo, account: account, github_id: 1, name: "hello-world")

        expect(EcosystemFileDetector).not_to receive(:uv_lock_exists?)

        expect { run }.to have_enqueued_job(CreateGraphUpdateJob)

        expect(UpdateConfig.last.package_manager).to eq(PackageManagers::GO_MODULES)
      end
    end

    context "when two rapid pushes occur on the same branch with different manifests" do
      let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
      let(:ref_name) { "refs/heads/main" }
      let(:first_commit_oid) { "aaaaaaa" }
      let(:second_commit_oid) { "bbbbbbb" }

      before do
        Rails.cache.clear
        allow(GitHubHelpers).to receive(:access_token_for).and_return("token")
      end

      def build_message(commit_oid:)
        payload = hydro_fixture(name: "update_graph_pypi", schema: "dependency_graph.v0.UpdateGraphEvent")
        payload[:graph_changes].first[:commit_oid] = commit_oid
        instance_double(
          Hydro::Consumer::ConsumerMessage,
          value: payload,
          timestamp: Time.now.utc,
          headers: { "X-GitHub-Tenant-ID" => "123", "X-GitHub-Tenant" => "github" },
        )
      end

      context "when feature flag is enabled" do
        it "correctly resolves to uv on the second push using commit_oid cache keys" do
          account = create(:account, :active, github_id: 1)
          create(:repo, account: account, github_id: 1)
          stub_monolith_feature(:dependabot_use_commit_oid_for_pm_resolution, actor: account.monolith_actor,
                                                                              enabled: true)

          # First push: pip manifest change — no uv.lock at this commit
          stub_request(:get, "#{github_url}repositories/1/contents/uv.lock?ref=#{first_commit_oid}").
            to_return(status: 404, body: { message: "Not Found" }.to_json)
          described_class.run(build_message(commit_oid: first_commit_oid))
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::PIP)

          # Second push: uv manifest added — uv.lock now exists at this commit.
          # Because commit_oid differs, the cache key is different, so a fresh lookup occurs.
          stub_request(:get, "#{github_url}repositories/1/contents/uv.lock?ref=#{second_commit_oid}").
            to_return(status: 200, body: { content: Base64.encode64("lockfile") }.to_json,
                      headers: { "Content-Type" => "application/json" })
          described_class.run(build_message(commit_oid: second_commit_oid))
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::UV)
        end
      end

      context "when feature flag is disabled" do
        it "incorrectly resolves to pip on the second push due to stale ref_name cache" do
          account = create(:account, :active, github_id: 1)
          create(:repo, account: account, github_id: 1)
          stub_monolith_feature(:dependabot_use_commit_oid_for_pm_resolution, actor: account.monolith_actor,
                                                                              enabled: false)

          # First push: pip manifest change — no uv.lock, cached under ref_name key
          stub_request(:get, "#{github_url}repositories/1/contents/uv.lock?ref=#{CGI.escape(ref_name)}").
            to_return(status: 404, body: { message: "Not Found" }.to_json)
          described_class.run(build_message(commit_oid: first_commit_oid))
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::PIP)

          # Second push: uv manifest added, but the stale cache (same ref_name key)
          # still returns false — wrongly resolves to pip instead of uv.
          described_class.run(build_message(commit_oid: second_commit_oid))
          expect(UpdateConfig.last.package_manager).to eq(PackageManagers::PIP)
        end
      end
    end
  end
end
