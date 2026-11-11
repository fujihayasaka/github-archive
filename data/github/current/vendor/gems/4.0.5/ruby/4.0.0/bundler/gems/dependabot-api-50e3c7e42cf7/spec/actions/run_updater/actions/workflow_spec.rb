# frozen_string_literal: true

require "rails_helper"

RSpec.describe RunUpdater::Actions::Workflow do
  include ActiveJob::TestHelper

  subject(:workflow) { described_class.new(update_job: update_job) }

  let(:repo) { update_job.update_config.repo }
  let(:run_action_step) do
    workflow.to_h.dig("jobs", "Dependabot", "steps").find do |step|
      step["name"] == "Run Dependabot"
    end
  end

  describe "#update_job_dir" do
    let(:update_job) { FactoryBot.create(:update_job, :version_update) }

    it "returns the correct path" do
      expect(workflow.update_job_dir).
        to eq("./dependabot-job-#{update_job.id}-#{update_job.updated_at.to_i}")
    end
  end

  context "with a security update" do
    let(:update_job) { FactoryBot.create(:update_job, :security_update, dependencies: ["activesupport"]) }

    it "uses the correct workflow name" do
      expect(workflow.run_name).to eql("bundler in /. for activesupport - Update ##{update_job.id}")
    end
  end

  context "with a graph update" do
    let(:update_job) { FactoryBot.create(:update_job, command: :graph) }

    it "uses the correct workflow name when configured by user" do
      expect(workflow.run_name).to eql("Configured Graph Update: bundler in /. ##{update_job.id}")
    end

    it "uses the correct workflow name when not configured by user" do
      update_job.update_config.update_schedule = "never"
      expect(workflow.run_name).to eql("Graph Update: bundler in /. ##{update_job.id}")
    end

    it "uses the correct workflow slug and label" do
      expect(workflow.workflow_name).to eql("Dependency Graph")
      expect(workflow.slug).to eql("update-graph")
    end

    it "uses the correct job name" do
      expect(workflow.to_h["jobs"]).to have_key("update-bundler-graph")
    end
  end

  context "when using directories on the update_job" do
    let(:update_job) do
      FactoryBot.create(:update_job, directories: ["/.", "/backend"], dependencies: ["activesupport"])
    end

    it "uses the correct workflow name" do
      expect(workflow.run_name).to eql("bundler in /., /backend for activesupport - Update ##{update_job.id}")
    end
  end

  context "when using directories on the update_config" do
    let(:update_config) { FactoryBot.create(:update_config, directory: nil, directories: ["/", "/backend"]) }
    let(:update_job) { FactoryBot.create(:update_job, update_config: update_config, dependencies: ["activesupport"]) }

    it "uses the correct workflow name" do
      expect(workflow.run_name).to eql("bundler in /., /backend for activesupport - Update ##{update_job.id}")
    end
  end

  context "when the repository has an action branch set" do
    let(:update_job) { FactoryBot.create(:update_job, :version_update) }

    before do
      described_class.set_branch_for(repo: repo, branch_name: "breaking-all-the-things")
    end

    it "checks out the action at the specified branch", :cloud do
      expect(run_action_step["uses"]).to eql("github/dependabot-action@breaking-all-the-things")
    end

    it "ignores specified branches in enterprise", :enterprise do
      expect(run_action_step["uses"]).to eql("github/dependabot-action@ghes-3.20")
    end

    it "reverts to the default when the specified branch is cleared", :cloud do
      described_class.clear_branch_for(repo: repo)

      expect(run_action_step["uses"]).to eql("github/dependabot-action@main")
    end
  end

  context "with a version update" do
    let(:update_job) { FactoryBot.create(:update_job, :version_update) }

    it "uses the correct workflow name" do
      expect(workflow.run_name).to eql("bundler in /. - Update ##{update_job.id}")
    end

    it "uses the correct version of the action", :cloud do
      expect(run_action_step["uses"]).to eql("github/dependabot-action@main")
    end

    it "uses the correct version of the action", :enterprise do
      expect(run_action_step["uses"]).to eql("github/dependabot-action@ghes-3.20")
    end

    it "uses the correct version of the action", :proxima do
      expect(run_action_step["uses"]).to eql("github/dependabot-action@main")
    end

    it "uses the correct runs-on labels for cloud", :cloud do
      expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eql(%w(ubuntu-latest))
    end

    it "uses the correct runs-on labels for enterprise", :enterprise do
      expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eql(%w(dependabot))
    end

    it "uses the correct runs-on labels for proxima", :proxima do
      expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eql(%w(ubuntu-latest))
    end

    it "sets a timeout on cloud", :cloud do
      expect(workflow.to_h.dig("jobs", "Dependabot", "timeout-minutes")).to eq(55)
    end

    it "sets a 1m timeout on cloud when feature enabled", :cloud do
      repo.enable_feature(:actions_timeout_1_minute)

      expect(workflow.to_h.dig("jobs", "Dependabot", "timeout-minutes")).to be(1)
    end

    it "sets a 180m timeout on cloud when feature enabled", :cloud do
      repo.enable_feature(:actions_long_timeout)

      expect(workflow.to_h.dig("jobs", "Dependabot", "timeout-minutes")).to be(180)
    end

    it "doesn't set a timeout for enterprise", :enterprise do
      expect(workflow.to_h.dig("jobs", "Dependabot", "timeout-minutes")).to be_nil
    end

    it "doesn't verify dependencies + connectivity or cleanup on cloud when not self-hosted", :cloud do
      verify_dependencies = workflow.to_h.dig("jobs", "Dependabot", "steps").find do |step|
        step["name"] == "Verify actions runner dependencies"
      end
      cleanup = workflow.to_h.dig("jobs", "Dependabot", "steps").find do |step|
        step["name"] == "Cleanup job directory"
      end
      run = workflow.to_h.dig("jobs", "Dependabot", "steps").find do |step|
        step["name"] == "Run Dependabot"
      end

      expect(verify_dependencies).to be_nil
      expect(cleanup).to be_nil
      expect(run.dig("env", "DEPENDABOT_DISABLE_CLEANUP")).to eq("1")
      expect(run.dig("env", "DEPENDABOT_ENABLE_CONNECTIVITY_CHECK")).to eq("0")
      expect(run.dig("env", "GITHUB_DEPENDABOT_JOB_TOKEN")).to an_instance_of(String)
      expect(run.dig("env", "GITHUB_DEPENDABOT_CRED_TOKEN")).to an_instance_of(String)
    end

    it "sets the GITHUB_REGISTRIES_PROXY environment variable", :cloud do
      run = workflow.to_h.dig("jobs", "Dependabot", "steps").find do |step|
        step["name"] == "Run Dependabot"
      end

      expect(run.dig("env", "GITHUB_REGISTRIES_PROXY")).to an_instance_of(String)
    end
  end

  describe "#to_h reports the correct workflow structure" do
    context "with OIDC disabled on the repo on the monolith" do
      let(:update_job) { FactoryBot.create(:update_job, :version_update) }

      before do
        stub_monolith_feature(
          :disable_oidc_auth,
          actor: repo.monolith_actor,
          enabled: true
        )
      end

      it "does not have permissions set" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "permissions")).to be_nil
      end
    end

    context "with OIDC disabled on the account on the monolith" do
      let(:update_job) { FactoryBot.create(:update_job, :version_update) }

      before do
        stub_monolith_feature(
          :disable_oidc_auth,
          actor: repo.account.monolith_actor,
          enabled: true
        )
      end

      it "does not have permissions set" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "permissions")).to be_nil
      end
    end

    context "with disable OIDC auth not enabled (default)" do
      let(:update_job) { FactoryBot.create(:update_job, :version_update) }

      before do
        stub_monolith_feature(
          :disable_oidc_auth,
          actor: repo.monolith_actor,
          enabled: false
        )
        stub_monolith_feature(
          :disable_oidc_auth,
          actor: repo.account.monolith_actor,
          enabled: false
        )
      end

      it "has the correct permissions" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "permissions")).to eq({
                                                                               "contents" => "read",
                                                                               "id-token" => "write",
                                                                               "packages" => "read",
                                                                             })
      end
    end
  end

  describe "self-hosted runner settings" do
    subject(:workflow) { described_class.new(update_job: update_job, runner_settings: runner_settings) }

    let(:update_job) { FactoryBot.create(:update_job, :version_update) }
    let(:runner_settings) { nil }

    before do
      # Make update_job self-hosted so it uses self_hosted_workflow
      update_job.update!(runner_type: UpdateJob::RUNNER_SELF_HOSTED)
    end

    context "with custom runner labels" do
      let(:runner_settings) do
        { runner_labels: %w(self-hosted custom), runner_group: nil }
      end

      it "uses custom runner labels" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eq(%w(self-hosted custom))
      end
    end

    context "with runner group and labels" do
      let(:runner_settings) do
        {
          runner_labels: %w(self-hosted custom),
          runner_group: "my-runner-group",
        }
      end

      it "uses hash format with group and labels" do
        runs_on = workflow.to_h.dig("jobs", "Dependabot", "runs-on")

        expect(runs_on).to eq({ "group" => "my-runner-group", "labels" => %w(self-hosted custom) })
      end
    end

    context "with single custom runner label" do
      let(:runner_settings) { { runner_labels: ["my-custom-runner"], runner_group: nil } }

      it "uses the single custom runner label" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eq(["my-custom-runner"])
      end
    end

    context "with empty runner labels" do
      let(:runner_settings) { { runner_labels: [], runner_group: nil } }

      it "falls back to default dependabot label" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eq(%w(dependabot))
      end
    end

    context "with nil runner_settings" do
      let(:runner_settings) { nil }

      it "falls back to default dependabot label" do
        expect(workflow.to_h.dig("jobs", "Dependabot", "runs-on")).to eq(%w(dependabot))
      end
    end
  end
end
