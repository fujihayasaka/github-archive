# frozen_string_literal: true

require "rails_helper"

RSpec.describe RunUpdater::Actions do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:updater) { described_class.new(update_job) }

  let(:update_job) { FactoryBot.create(:update_job, :version_update, :enqueued) }
  let(:repo) { update_job.update_config.repo }
  let(:job_token) { "xxx" }
  let(:credentials_token) { "yyy" }
  let(:execution_id) { "75b5f5dd-870f-4a44-8068-70380837fe80" }
  let(:workflow_run_id) { 9876543210 }
  let(:mock_octokit) { instance_double(Octokit::Client) }

  let(:octokit_error) do
    Octokit::Error.from_response(error_response)
  end

  let(:github_graphql_endpoint) { Dependabot::Application.target_github_graphql_endpoint }

  let(:dependency_update_body) do
    "github_responses/mark_github_job_errored/success.json"
  end

  before do
    github_token = "top secret"
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return(github_token)

    # Ensure the legacy (flag-off) path is used by default in these specs.
    # The flag-on path is tested in the dedicated context block below.
    stub_monolith_feature(
      :dependabot_use_internal_dynamic_workflow_endpoint,
      actor: repo.monolith_actor,
      enabled: false,
    )

    allow(GitHubHelpers::ClientWithRetries).
      to receive(:new).
      with(account: repo.account).
      and_return(mock_octokit)

    allow(mock_octokit).to receive(:post).
      and_return(
        Sawyer::Resource.new(
          Sawyer::Agent.new("https://api.github.com"),
          {
            execution_id: execution_id,
            workflow_run_id: workflow_run_id,
          }
        )
      )

    stub_request(:post, github_graphql_endpoint).
      to_return(
        status: 200,
        body: dependency_update_body,
        headers: { "Content-Type" => "application/json" },
      )
  end

  # rubocop:disable RSpec/ExampleLength
  it "triggers the workflow on cloud", :cloud do
    freeze_time do
      updater.run

      expect(mock_octokit).
        to have_received(:post).
        with("repositories/#{repo.github_id}/actions/dynamic", satisfy do |args|
          expect(args[:headers]).not_to be_present

          expect(args[:ref]).to eq(repo.default_branch)
          expect(args[:inputs]).
            to match(hash_including({
                                      jobId: update_job.id.to_s,
                                      dependabotApiUrl: "https://dependabot-actions.githubapp.com",
                                      updaterImage: "",
                                      workingDirectory: a_string_starting_with(%(./dependabot-job-#{update_job.id}-)),
                                    }))
          expect(args[:workflow_name]).to eq("Dependabot Updates")
          expect(args[:slug]).to eq("dependabot-updates")
          workflow = YAML.safe_load(args[:workflow])
          expect(workflow["name"]).to eq("bundler in /. - Update ##{update_job.id}")
          expect(workflow["on"]).to eq("dynamic")
          jobs = workflow["jobs"]
          expect(jobs.length).to eq(1)
          expect(jobs.keys.first).to eq("Dependabot")
          job = jobs.values.first
          expect(job["runs-on"]).to eq(%w(ubuntu-latest))
          expect(job["steps"].count).to be(2)
          expect(job["steps"].pluck("name")).to eql([
                                                      "Create job directory",
                                                      "Run Dependabot",
                                                    ])
          true
        end).
        once

      expect(update_job.reload.actions_external_id).to eq(execution_id)
      expect(update_job.reload.actions_workflow_run_id).to eq(workflow_run_id)
    end
  end
  # rubocop:enable RSpec/ExampleLength

  context "when an UpdaterVersion is set" do
    before do
      FactoryBot.create(:updater_version, env: "prod", ecosystem: "gomod", version: "123")
    end

    # go is more interesting for testing since it is called something different internally than externally
    let(:update_config) { FactoryBot.create(:update_config, package_manager: "go_modules") }
    let(:update_job) { FactoryBot.create(:update_job, :version_update, :enqueued, update_config: update_config) }

    it "sends an ecosystem-specific updater image", :cloud do
      updater.run

      expect(mock_octokit).
        to have_received(:post).
        with("repositories/#{repo.github_id}/actions/dynamic", satisfy do |args|
          expect(args[:inputs][:updaterImage]).to eq("ghcr.io/dependabot/dependabot-updater-gomod:123")
          true
        end).
        once

      expect(update_job.reload.actions_external_id).to eq(execution_id)
      expect(update_job.reload.actions_workflow_run_id).to eq(workflow_run_id)
    end

    context "and ghes_mode is enabled" do
      it "doesn't send an ecosystem-specific updater image", :cloud do
        repo.enable_feature(:ghes_mode) # rubocop:disable Dependabot/NoLocalFeatureFlags

        updater.run

        expect(mock_octokit).
          to have_received(:post).
          with("repositories/#{repo.github_id}/actions/dynamic", satisfy do |args|
                                                                   expect(args[:inputs][:updaterImage]).to eq(nil)
                                                                   true
                                                                 end).
          once
      end
    end
  end

  # rubocop:disable RSpec/ExampleLength
  it "triggers the workflow on enterprise", :enterprise do
    freeze_time do
      allow(Prius).
        to receive(:get).
        and_call_original
      allow(Prius).
        to receive(:get).with(:target_github_url).
        and_return("https://ghes.com")
      allow(Prius).
        to receive(:get).with(:dependabot_api_endpoint).
        and_return("https://ghes.com/_dependabot")

      updater.run

      expect(mock_octokit).
        to have_received(:post).
        with("repositories/#{repo.github_id}/actions/dynamic", satisfy do |args|
          expect(args[:headers]).not_to be_present

          expect(args[:ref]).to eq(repo.default_branch)
          expect(args[:inputs]).
            to match(hash_including({
                                      jobId: update_job.id.to_s,
                                      dependabotApiUrl: "https://ghes.com/_dependabot",
                                      updaterImage: "",
                                      workingDirectory: a_string_starting_with(%(./dependabot-job-#{update_job.id})),
                                    }))
          expect(args[:workflow_name]).to eq("Dependabot Updates")
          expect(args[:slug]).to eq("dependabot-updates")
          workflow = YAML.safe_load(args[:workflow])
          expect(workflow["name"]).to eq("bundler in /. - Update ##{update_job.id}")
          expect(workflow["on"]).to eq("dynamic")
          jobs = workflow["jobs"]
          expect(jobs.length).to eq(1)
          expect(jobs.keys.first).to eq("Dependabot")
          job = jobs.values.first
          expect(job["runs-on"]).to eq(%w(dependabot))
          expect(job["steps"].count).to be(4)
          expect(job["steps"].pluck("name")).to eql([
                                                      "Verify actions runner dependencies",
                                                      "Create job directory",
                                                      "Run Dependabot",
                                                      "Cleanup job directory",
                                                    ])
          true
        end).
        once

      expect(update_job.reload.actions_external_id).to eq(execution_id)
      expect(update_job.reload.actions_workflow_run_id).to eq(workflow_run_id)
    end
  end
  # rubocop:enable RSpec/ExampleLength

  it "triggers the workflow on enterprise", :proxima do # rubocop:disable RSpec/ExampleLength
    freeze_time do
      allow(Prius).
        to receive(:get).
        and_call_original
      allow(Prius).
        to receive(:get).with(:target_github_url).
        and_return("https://proxima.ghe.com")
      allow(Prius).
        to receive(:get).with(:dependabot_api_endpoint).
        and_return("https://dependabot-api-proxima.githubapp.com")

      updater.run

      expect(mock_octokit).
        to have_received(:post).
        with("repositories/#{repo.github_id}/actions/dynamic", satisfy do |args|
          expect(args[:ref]).to eq(repo.default_branch)
          expect(args[:inputs]).
            to match(hash_including({
                                      jobId: update_job.id.to_s,
                                      dependabotApiUrl: "https://dependabot-api.#{repo.account.tenant.slug}.ghe.com",
                                      updaterImage: "",
                                      workingDirectory: a_string_starting_with(%(./dependabot-job-#{update_job.id}-)),
                                    }))
          expect(args[:workflow_name]).to eq("Dependabot Updates")
          expect(args[:slug]).to eq("dependabot-updates")
          workflow = YAML.safe_load(args[:workflow])
          expect(workflow["name"]).to eq("bundler in /. - Update ##{update_job.id}")
          expect(workflow["on"]).to eq("dynamic")
          jobs = workflow["jobs"]
          expect(jobs.length).to eq(1)
          expect(jobs.keys.first).to eq("Dependabot")
          job = jobs.values.first
          expect(job["runs-on"]).to eq(%w(ubuntu-latest))
          expect(job["steps"].count).to be(2)
          expect(job["steps"].pluck("name")).to eql([
                                                      "Create job directory",
                                                      "Run Dependabot",
                                                    ])
          true
        end).
        once

      expect(update_job.reload.actions_external_id).to eq(execution_id)
      expect(update_job.reload.actions_workflow_run_id).to eq(workflow_run_id)
    end
  end

  context "when internal dynamic workflow endpoint is enabled", :cloud do
    let(:hmac_key) { "test-hmac-key" }

    before do
      stub_monolith_feature(
        :dependabot_use_internal_dynamic_workflow_endpoint,
        actor: repo.monolith_actor,
        enabled: true,
      )

      allow(Prius).to receive(:get).and_call_original
      allow(Prius).to receive(:get).
        with(:api_internal_actions_dynamic_workflows_hmac_client_key).
        and_return(hmac_key)

      allow(GitHubHelpers::ClientWithRetries).
        to receive(:new).
        with(account: repo.account, hmac_key: hmac_key).
        and_return(mock_octokit)
    end

    it "dispatches via the internal endpoint with prevent_reruns" do
      updater.run

      expect(mock_octokit).to have_received(:post).with(
        "internal/repositories/#{repo.github_id}/actions/dynamic",
        satisfy do |args|
          expect(args[:prevent_reruns]).to be(true)
          expect(args[:workflow_name]).to eq("Dependabot Updates")
          expect(args[:slug]).to eq("dependabot-updates")
          expect(args[:ref]).to eq(repo.default_branch)
          expect(args[:inputs][:jobId]).to eq(update_job.id.to_s)
          true
        end,
      )
    end

    it "stores execution_id and workflow_run_id" do
      updater.run

      expect(update_job.reload.actions_external_id).to eq(execution_id)
      expect(update_job.reload.actions_workflow_run_id).to eq(workflow_run_id)
    end
  end

  context "when the update_config has a target_branch", :cloud do
    before { update_job.update_config.update!(target_branch: "feature-branch") }

    it "dispatches the workflow against target_branch instead of default_branch" do
      updater.run

      expect(mock_octokit).to have_received(:post).with(
        "repositories/#{repo.github_id}/actions/dynamic",
        satisfy do |args|
          expect(args[:ref]).to eq("feature-branch")
          true
        end,
      )
    end
  end

  context "when the update job has a base_commit_sha set", :cloud do
    before { update_job.update!(base_commit_sha: "abc123def456") }

    it "still dispatches with the branch as the workflow ref, not the SHA" do
      updater.run

      expect(mock_octokit).to have_received(:post).with(
        "repositories/#{repo.github_id}/actions/dynamic",
        satisfy do |args|
          expect(args[:ref]).to eq(repo.default_branch)
          expect(args[:ref]).not_to eq("abc123def456")
          true
        end,
      )
    end
  end

  describe "initialization" do
    it "can be initialized with just an update job" do
      expect { described_class.new(update_job) }.not_to raise_error
    end

    it "can be initialized with update job and runner settings" do
      runner_settings = { runner_labels: %w(custom), runner_group: "test-group" }
      expect { described_class.new(update_job, runner_settings) }.not_to raise_error
    end

    it "can be initialized with update job and nil runner settings" do
      expect { described_class.new(update_job, nil) }.not_to raise_error
    end

    it "passes runner settings to the workflow" do
      runner_settings = { runner_labels: %w(custom), runner_group: "test-group" }
      updater = described_class.new(update_job, runner_settings)

      expect(RunUpdater::Actions::Workflow).to receive(:new).with(
        update_job: update_job,
        runner_settings: runner_settings
      ).and_call_original

      updater.send(:workflow)
    end
  end
end
