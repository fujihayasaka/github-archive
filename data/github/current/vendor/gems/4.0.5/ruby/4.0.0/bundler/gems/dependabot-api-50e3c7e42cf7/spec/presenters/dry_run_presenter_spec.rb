# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe DryRunPresenter do
  include ProximaHelpers

  subject(:presenter) do
    described_class.new(update_job: update_job)
  end

  let(:update_job) do
    FactoryBot.create(:update_job, update_config: update_config)
  end
  let(:update_config) { FactoryBot.create(:update_config, repo: repo) }
  let(:repo) { FactoryBot.create(:repo, :public) }

  describe "#cli_command" do
    subject(:cli_command) { presenter.cli_command }

    it "builds a command to be run" do
      stub_proxima_repo_request(repo_id: repo.github_id, fixture: "proxima_repo")

      # intentionally added spaces before to ensure these aren't symbols which as_json produces
      expect(cli_command).to start_with("---\njob:\n  command:")
      expect(cli_command).to include(" repo: hmarr/business")
      expect(cli_command).to include(" directory: \"/\"")
    end
  end

  describe "#command" do
    subject(:command) { presenter.command }

    it do
      expect(command).to start_with(
        "bin/dry-run.rb bundler \"hmarr/business\" --dir=\"/\""
      )
    end

    context "with optional update config settings" do
      let(:update_config) do
        FactoryBot.create(
          :update_config,
          repo: repo,
          directory: "/app",
          target_branch: "develop",
          requirements_update_strategy: "bump_versions",
        )
      end

      it "includes flags" do
        expect(command).to include(
          "--dir=\"/app\" --branch=\"develop\" "\
          "--requirements-update-strategy=\"bump_versions\""
        )
      end
    end

    context "with security advisories" do
      let(:update_job) do
        FactoryBot.create(:update_job, :security, dependencies: ["rails"],
                                                  update_config: update_config,
                                                  trigger_type: "push")
      end

      before do
        advisory = FactoryBot.build_stubbed(:github_security_advisory,
                                            package_manager: "bundler",
                                            dependency_name: "rails",
                                            affected_versions: ["> 2.5.0, <= 2.5.14"],
                                            patched_versions: ["~> 1.0.0"])
        allow(GitHubSecurityAdvisory).to receive(:fetch).
          and_return([advisory])
      end

      it "includes advisories" do
        expect(command).to include(
          "SECURITY_ADVISORIES='[{\"dependency-name\":\"rails\",\"patched-versions\":[],\"unaffected-versions\""\
          ":[],\"affected-versions\":[\"> 2.5.0, <= 2.5.14\"]}]' \\\n"\
          "  bin/dry-run.rb bundler \"hmarr/business\""
        )
      end

      it "includes flags" do
        expect(command).to include(
          "--dep=\"rails\" --security-updates-only"
        )
      end
    end

    context "with ignore conditions" do
      # 3 specifies the number of fractional digits for seconds
      let(:timestamp) do
        Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
      end
      let(:update_job) do
        FactoryBot.create(:update_job, :security, dependencies: ["rails"],
                                                  update_config: update_config,
                                                  trigger_type: "push")
      end

      before do
        FactoryBot.create(:ignore_condition,
                          update_config: update_config,
                          dependency_name: "business",
                          version_requirement: "> 1, <= 2",
                          updated_at: timestamp)
        allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
      end

      it "includes ignores" do
        expect(command).to include(
          "IGNORE_CONDITIONS='[{\"dependency-name\":\"business\","\
          "\"version-requirement\":\"> 1, <= 2\","\
          "\"source\":\"@dependabot ignore command\","\
          "\"updated-at\":\"2020-04-01 00:00:00 UTC\"}]' \\\n"\
          "  bin/dry-run.rb bundler \"hmarr/business\""
        )
      end
    end

    context "with a private repo" do
      let(:repo) { FactoryBot.create(:repo, private: true) }

      it "prepends some debugger instructions" do
        expect(command).to start_with("https://github.com/github/dependabot-update-debugger/blob/main/README.md")
      end
    end

    context "with registries" do
      let(:registry) { FactoryBot.create(:registry, source: repo) }

      before do
        UpdateConfigRegistry.create(update_config: update_config, registry_name: registry.name)
      end

      it "includes the LOCAL_CONFIG_VARIABLES env variable with the serialized registry details" do
        expect(command).to include(
          "LOCAL_CONFIG_VARIABLES='[{\"type\":\"rubygems_server\",\"host\":\"gem.fury.io\","\
          "\"token\":\"${{secrets.GEMFURY}}\"}]'"
        )
      end

      it "includes debugger instructions" do
        expect(command).to include("https://github.com/github/dependabot-update-debugger/blob/main/README.md")
      end
    end
  end
end
