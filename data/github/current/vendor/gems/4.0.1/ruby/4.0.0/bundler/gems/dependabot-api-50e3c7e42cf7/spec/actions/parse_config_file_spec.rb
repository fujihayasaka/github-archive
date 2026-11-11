# frozen_string_literal: true

require "rails_helper"

RSpec.describe ParseConfigFile do
  subject(:action) do
    described_class.new(
      config_file: config_file,
      repo: repo
    )
  end

  let(:config_file) do
    OpenStruct.new(
      path: ".github/dependabot.yml",
      content: config_file_contents,
    )
  end

  let(:repo) { FactoryBot.create(:repo) }

  context "with a valid config file" do
    let(:config_file_contents) { fixture("config_files/minimal.yml") }

    it "returns details of the update configs" do
      time_of_day = repo.default_update_schedule_time_of_day
      hour, min = time_of_day.split(":").map(&:to_i)

      expect(action.updates).to eq(
        [
          {
            "package-manager" => "bundler",
            "directory" => "/.",
            "enable-beta-ecosystems" => false,
            "update-schedule" => "daily",
            "target-branch" => nil,
            "lockfile-only" => false,
            "requirements-update-strategy" => nil,
            "allowed-updates" => [
              { "dependency_type" => "direct", "update_type" => "all" },
            ],
            "custom-labels" => nil,
            "default-assignees" => nil,
            "default-milestone" => nil,
            "default-reviewers" => nil,
            "ignore-conditions" => nil,
            "commit-message-prefix" => nil,
            "commit-message-prefix-development" => nil,
            "cooldown" => nil,
            "commit-message-include-scope" => nil,
            "open-pull-requests-limit" => nil,
            "pull-request-branch-name-separator" => nil,
            "rebase-strategy" => nil,
            "update-schedule-day-of-week" => nil,
            "update-schedule-time-of-day" => time_of_day,
            "update-schedule-timezone" => "UTC",
            "registries" => nil,
            "vendor" => false,
            "insecure-external-code-execution" => nil,
            "groups" => nil,
            "update-schedule-cron-expression" => "#{min} #{hour} * * 1-5 UTC",
            "multi_ecosystem_config_id" => nil,
            "multi_ecosystem_config_name" => nil,
            "multi_ecosystem_config_patterns" => nil,
            "exclude-paths" => nil,
          },
        ],
      )
    end

    context "with auto-merge enabled" do
      let(:config_file_contents) do
        fixture("config_files/auto_merge.yml")
      end

      it "returns auto-merge boolean" do
        expect(action.automerge).to eq(true)
      end

      context "with days-before-merge set" do
        let(:config_file_contents) do
          fixture("config_files/auto_merge_days_before_merge.yml")
        end

        it "returns days-before-merge as an integer" do
          expect(action.days_before_automerge).to eq(5)
        end
      end
    end

    context "with optional properties" do
      let(:config_file_contents) do
        fixture("config_files/optional_properties.yml")
      end

      it "returns details of the update configs" do
        time_of_day = repo.default_update_schedule_time_of_day
        hour, min = time_of_day.split(":").map(&:to_i)

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => false,
              "update-schedule-cron-expression" => "#{min} #{hour} * * 1-5 UTC",
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "default-reviewers" => nil,
              "default-assignees" => %w(drwho),
              "default-milestone" => 12,
              "custom-labels" => %w(security deps),
              "lockfile-only" => false,
              "allowed-updates" => [
                { "dependency_type" => "all" },
                { "dependency_name" => "rails" },
              ],
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "ignore-conditions" => [{
                "dependency_name" => "rails",
                "update_types" => nil,
                "version_requirement" => "> 6.0",
              }, {
                "dependency_name" => "rspec",
                "update_types" => nil,
                "version_requirement" => ">= 0",
              },],
              "commit-message-prefix" => "chore",
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => true,
              "insecure-external-code-execution" => "deny",
              "groups" => {
                "development" => {
                  "applies-to" => "security-updates",
                  "patterns" => [
                    "dev*",
                  ],
                },
              },
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with a group-by configuration" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "pip"
              directories:
                - "/service-a"
                - "/service-b"
              schedule:
                interval: "weekly"
              groups:
                per-dependency:
                  group-by: dependency-name
        YAML
      end

      it "returns group-by in the groups hash" do
        updates = action.updates
        expect(updates.length).to eq(1)
        expect(updates.first["groups"]).to eq(
          {
            "per-dependency" => {
              "group-by" => "dependency-name",
            },
          }
        )
        expect(updates.first["directories"]).to eq(["/service-a", "/service-b"])
      end
    end

    context "with group-by alongside other group rules" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "npm"
              directory: "/"
              schedule:
                interval: "daily"
              groups:
                dev-per-dependency:
                  patterns:
                    - "dev-*"
                  group-by: dependency-name
        YAML
      end

      it "returns both group-by and patterns in the groups hash" do
        updates = action.updates
        expect(updates.length).to eq(1)
        expect(updates.first["groups"]).to eq(
          {
            "dev-per-dependency" => {
              "patterns" => ["dev-*"],
              "group-by" => "dependency-name",
            },
          }
        )
      end
    end

    context "with a optional cronjob property" do
      let(:config_file_contents) do
        fixture("config_files/optional_cronjob_property.yml")
      end

      it "returns details of the update configs" do
        # For cron interval, time is normalized but not used for the cron expression
        time_of_day = repo.default_update_schedule_time_of_day

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule-cron-expression" => "0 5 * * * UTC",
              "update-schedule" => "cron",
              "target-branch" => "rollout",
              "default-reviewers" => nil,
              "default-assignees" => %w(drwho),
              "default-milestone" => 12,
              "custom-labels" => %w(security deps),
              "lockfile-only" => false,
              "allowed-updates" => [
                { "dependency_type" => "all" },
                { "dependency_name" => "rails" },
              ],
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "ignore-conditions" => [{
                "dependency_name" => "rails",
                "update_types" => nil,
                "version_requirement" => "> 6.0",
              }, {
                "dependency_name" => "rspec",
                "update_types" => nil,
                "version_requirement" => ">= 0",
              },],
              "commit-message-prefix" => "chore",
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => true,
              "insecure-external-code-execution" => "deny",
              "groups" => {
                "development" => {
                  "applies-to" => "security-updates",
                  "patterns" => [
                    "dev*",
                  ],
                },
              },
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with a quarterly schedule property" do
      let(:config_file_contents) do
        fixture("config_files/quarterly_schedule_property.yml")
      end

      it "returns details of the update configs" do
        time_of_day = repo.default_update_schedule_time_of_day
        hour, min = time_of_day.split(":").map(&:to_i)

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "quarterly",
              "update-schedule-cron-expression" => "#{min} #{hour} 1 1,4,7,10 * UTC",
              "target-branch" => "rollout",
              "default-reviewers" => nil,
              "default-assignees" => %w(drwho),
              "default-milestone" => 12,
              "custom-labels" => %w(security deps),
              "lockfile-only" => false,
              "allowed-updates" => [
                { "dependency_type" => "all" },
                { "dependency_name" => "rails" },
              ],
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "ignore-conditions" => [{
                "dependency_name" => "rails",
                "update_types" => nil,
                "version_requirement" => "> 6.0",
              }, {
                "dependency_name" => "rspec",
                "update_types" => nil,
                "version_requirement" => ">= 0",
              },],
              "commit-message-prefix" => "chore",
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => true,
              "insecure-external-code-execution" => "deny",
              "groups" => {
                "development" => {
                  "applies-to" => "security-updates",
                  "patterns" => [
                    "dev*",
                  ],
                },
              },
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with a semiannually schedule property" do
      let(:config_file_contents) do
        fixture("config_files/semiannually_schedule_property.yml")
      end

      it "returns details of the update configs" do
        time_of_day = repo.default_update_schedule_time_of_day
        hour, min = time_of_day.split(":").map(&:to_i)

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "semiannually",
              "update-schedule-cron-expression" => "#{min} #{hour} 1 1,7 * UTC",
              "target-branch" => "rollout",
              "default-reviewers" => nil,
              "default-assignees" => %w(drwho),
              "default-milestone" => 12,
              "custom-labels" => %w(security deps),
              "lockfile-only" => false,
              "allowed-updates" => [
                { "dependency_type" => "all" },
                { "dependency_name" => "rails" },
              ],
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "ignore-conditions" => [{
                "dependency_name" => "rails",
                "update_types" => nil,
                "version_requirement" => "> 6.0",
              }, {
                "dependency_name" => "rspec",
                "update_types" => nil,
                "version_requirement" => ">= 0",
              },],
              "commit-message-prefix" => "chore",
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => true,
              "insecure-external-code-execution" => "deny",
              "groups" => {
                "development" => {
                  "applies-to" => "security-updates",
                  "patterns" => [
                    "dev*",
                  ],
                },
              },
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with a yearly schedule property" do
      let(:config_file_contents) do
        fixture("config_files/yearly_schedule_property.yml")
      end

      it "returns details of the update configs" do
        time_of_day = repo.default_update_schedule_time_of_day
        hour, min = time_of_day.split(":").map(&:to_i)

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "yearly",
              "update-schedule-cron-expression" => "#{min} #{hour} 1 1 * UTC",
              "target-branch" => "rollout",
              "default-reviewers" => nil,
              "default-assignees" => %w(drwho),
              "default-milestone" => 12,
              "custom-labels" => %w(security deps),
              "lockfile-only" => false,
              "allowed-updates" => [
                { "dependency_type" => "all" },
                { "dependency_name" => "rails" },
              ],
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "ignore-conditions" => [{
                "dependency_name" => "rails",
                "update_types" => nil,
                "version_requirement" => "> 6.0",
              }, {
                "dependency_name" => "rspec",
                "update_types" => nil,
                "version_requirement" => ">= 0",
              },],
              "commit-message-prefix" => "chore",
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => true,
              "insecure-external-code-execution" => "deny",
              "groups" => {
                "development" => {
                  "applies-to" => "security-updates",
                  "patterns" => [
                    "dev*",
                  ],
                },
              },
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with full customisation of the commit message" do
      let(:config_file_contents) do
        fixture("config_files/commit_message_prefixes.yml")
      end

      it "returns details of the update configs" do
        time_of_day = repo.default_update_schedule_time_of_day
        hour, min = time_of_day.split(":").map(&:to_i)

        expect(action.updates).to eq(
          [
            {
              "package-manager" => "bundler",
              "directory" => "/.",
              "enable-beta-ecosystems" => false,
              "update-schedule" => "daily",
              "target-branch" => nil,
              "lockfile-only" => false,
              "requirements-update-strategy" => nil,
              "allowed-updates" => [
                { "dependency_type" => "direct", "update_type" => "all" },
              ],
              "custom-labels" => nil,
              "default-assignees" => nil,
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => "fix",
              "commit-message-prefix-development" => "chore",
              "cooldown" => nil,
              "commit-message-include-scope" => true,
              "open-pull-requests-limit" => nil,
              "pull-request-branch-name-separator" => nil,
              "rebase-strategy" => nil,
              "update-schedule-day-of-week" => nil,
              "update-schedule-time-of-day" => time_of_day,
              "update-schedule-timezone" => "UTC",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "#{min} #{hour} * * 1-5 UTC",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "with all package managers" do
      let(:config_file_contents) do
        fixture("config_files/all_package_managers.yml")
      end

      it "returns details of the update configs" do
        expect(action.updates).to eq(
          [
            {
              "package-manager" => "npm_and_yarn",
              "directory" => "/package",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "develop",
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "disabled",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "bundler",
              "directory" => "/rb",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => "bump_versions",
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "go_modules",
              "directory" => "/go",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "nuget",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "composer",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => "lockfile_only",
              "lockfile-only" => true,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "cargo",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "devcontainers",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "dotnet_sdk",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "maven",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "gradle",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "hex",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => "lockfile_only",
              "lockfile-only" => true,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "elm",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "pip",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => "lockfile_only",
              "lockfile-only" => true,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "docker",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "docker_compose",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "terraform",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "weekly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(deps),
              "default-assignees" => %w(drwho bot/sec),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 2 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "submodules",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "github_actions",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "pub",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => "bump_versions",
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "rust_toolchain",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "swift",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "bun",
              "directory" => "/package",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "develop",
              "requirements-update-strategy" => "bump_versions_if_necessary",
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "disabled",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "uv",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "vcpkg",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "monthly",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 1 * * Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "helm",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "conda",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "julia",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "bazel",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "opentofu",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
            {
              "package-manager" => "pre_commit",
              "directory" => "/.",
              "enable-beta-ecosystems" => true,
              "update-schedule" => "daily",
              "target-branch" => "rollout",
              "requirements-update-strategy" => nil,
              "lockfile-only" => false,
              "allowed-updates" => [{ "dependency_type" => "direct" }],
              "custom-labels" => %w(security deps),
              "default-assignees" => %w(drwho),
              "default-milestone" => nil,
              "default-reviewers" => nil,
              "ignore-conditions" => nil,
              "commit-message-prefix" => nil,
              "commit-message-prefix-development" => nil,
              "cooldown" => nil,
              "commit-message-include-scope" => nil,
              "open-pull-requests-limit" => 5,
              "update-schedule-time-of-day" => "20:00",
              "update-schedule-day-of-week" => "tuesday",
              "update-schedule-timezone" => "Europe/Amsterdam",
              "rebase-strategy" => "auto",
              "pull-request-branch-name-separator" => "-",
              "registries" => nil,
              "vendor" => false,
              "insecure-external-code-execution" => nil,
              "groups" => nil,
              "update-schedule-cron-expression" => "0 20 * * 1-5 Europe/Amsterdam",
              "multi_ecosystem_config_id" => nil,
              "multi_ecosystem_config_name" => nil,
              "multi_ecosystem_config_patterns" => nil,
              "exclude-paths" => nil,
            },
          ],
        )
      end
    end

    context "when the formerly beta pub ecosystem does not have the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/pub_without_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "when the formerly beta pub ecosystem still has the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/pub_with_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "with the formerly beta swift ecosystem that does not have the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/swift_without_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "when the formerly beta swift ecosystem still has the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/swift_with_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "with the formerly beta devcontainers ecosystem does not have the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/devcontainers_without_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "when the formerly beta devcontainers ecosystem with the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) { fixture("config_files/devcontainers_with_beta_ecosystems.yml") }

      it "doesn't raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "with an invalid value for enable-beta-ecosystems" do
      let(:config_file_contents) { fixture("config_files/invalid_enable_beta_ecosystems.yml") }

      it "raises an error" do
        expect { action.updates }.
          to raise_error(described_class::Invalid) do |error|
            expect(error.message).to eq(
              "The property '#/enable-beta-ecosystems' of type string did not match the following type: boolean"
            )
          end
      end
    end

    context "with package manager that supports insecure-external-code-execution property but config doesn't set it" do
      let(:config_file_contents) do
        fixture("config_files/bundler_with_registry_with_unspecified_code_execution.yml")
      end

      it "defaults to nil" do
        config = action.updates.first
        expect(config["insecure-external-code-execution"]).to eq(nil)
      end
    end

    context "with bundler that sets insecure-external-code-execution property" do
      let(:config_file_contents) do
        fixture("config_files/bundler_with_registry_with_code_execution_allowed.yml")
      end

      it "sets property to the specified value" do
        config = action.updates.first
        expect(config["insecure-external-code-execution"]).to eq("allow")
      end
    end

    context "with mix that sets insecure-external-code-execution property" do
      let(:config_file_contents) do
        fixture("config_files/mix_with_gitsource_external_code_execution.yml")
      end

      it "sets property to the specified value" do
        config = action.updates.first
        expect(config["insecure-external-code-execution"]).to eq("allow")
      end
    end

    context "with python that sets insecure-external-code-execution property" do
      let(:config_file_contents) do
        fixture("config_files/python_with_index_external_code_execution.yml")
      end

      it "sets property to the specified value" do
        config = action.updates.first
        expect(config["insecure-external-code-execution"]).to eq("allow")
      end
    end

    context "with maven version requirements" do
      let(:config_file_contents) { fixture("config_files/maven_with_ignores.yml") }

      it "validates the version requirements" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "with the enable-beta-ecosystems flag enabled" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          enable-beta-ecosystems: true
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "includes enable-beta-ecosystems true in the update config" do
        expect(action.updates.first["enable-beta-ecosystems"]).to eq(true)
      end

      context "with a beta ecosystem" do
        before do
          allow(Ecosystems).to receive(:beta?).with("bundler").and_return(true)
        end

        it "updates without error" do
          expect { action.run }.not_to raise_error
        end
      end
    end

    context "with the enable-beta-ecosystems flag disabled" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          enable-beta-ecosystems: false
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "includes enable-beta-ecosystems false in the update config" do
        expect(action.updates.first["enable-beta-ecosystems"]).to eq(false)
      end

      context "with a beta ecosystem" do
        before do
          allow(Ecosystems).to receive(:beta?).with("bundler").and_return(true)
        end

        it "raises an error" do
          expect { action.run }.
            to raise_error(described_class::Invalid) do |error|
              expect(error.message).to eq(
                "The enable-beta-ecosystems setting must be true to use the package-ecosystem bundler."
              )
            end
        end
      end
    end

    context "without the enable-beta-ecosystems flag" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "defaults enable-beta-ecosystems to false" do
        expect(action.updates.first["enable-beta-ecosystems"]).to eq(false)
      end
    end
  end

  context "with empty labels" do
    subject(:custom_labels) do
      update_config_details = action.updates
      update_config_details.first["custom-labels"]
    end

    let(:config_file_contents) do
      fixture("config_files/empty_labels.yml")
    end

    it { is_expected.to eq([]) }
  end

  context "with duplicate labels on a config" do
    let(:config_file_contents) do
      fixture("config_files/duplicate_labels.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error(described_class::Invalid) do |error|
          expect(error.message).to eq(
            "The property '#/updates/0/labels' contained duplicated "\
            "array values"
          )
        end
    end
  end

  context "with valid update groups" do
    let(:config_file_contents) { fixture("config_files/bundler_with_update_groups.yml") }

    it "includes update groups in the corresponding update" do
      expect(action.updates.length).to be 1
      expect(action.updates.first["groups"]).
        to eq({
                "my-update-group" => {
                  "patterns" => %w(rails hanami),
                },
                "yet-another-group" => {
                  "patterns" => %w(rspec rubocop*),
                  "exclude-patterns" => %w(rubocop-ast),
                },
              })
    end
  end

  context "with invalid update groups" do
    let(:config_file_contents) { fixture("config_files/invalid_update_group.yml") }

    it "returns includes update groups in the update" do
      expect { action.updates }.
        to raise_error(described_class::Invalid) do |error|
        expect(error.message).to eq(
          "The property '#/updates/0/groups/invalid/patterns' "\
          "of type null did not match the following type: array"
        )
      end
    end
  end

  context "with an unparseable config file" do
    let(:config_file_contents) { "'" }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error(described_class::Unparseable) do |error|
          expect(error.message).to eq(
            "(<unknown>): found unexpected end of stream while "\
            "scanning a quoted scalar at line 1 column 1"
          )
        end
    end
  end

  context "with a bad alias" do
    let(:config_file_contents) { fixture("config_files/bad_alias.yml") }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Unparseable)
          expect(error.message).to eq("YAML aliases are not supported")
        end
    end
  end

  context "with a bad Ruby object" do
    let(:config_file_contents) { fixture("config_files/bad_ruby_object.yml") }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Unparseable)
          expect(error.message).
            to eq("Tried to load unspecified class: DateTime")
        end
    end
  end

  context "with a config file that evaluates as a string" do
    let(:config_file_contents) { "hi" }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to include("Top level entity must be an Object, not a String")
        end
    end
  end

  context "with a config file that evaluates as an empty hash" do
    let(:config_file_contents) { "version: 2" }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/' did not contain a "\
                  "required property of 'updates'")
        end
    end
  end

  context "with a config file that sets updates to a string" do
    let(:config_file_contents) { "version: 2\nupdates: bad" }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates' of type string did "\
                  "not match the following type: array")
        end
    end
  end

  context "with an invalid package manager" do
    let(:config_file_contents) do
      fixture("config_files/invalid_package_manager.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to include("#/updates/0/package-ecosystem' value "\
                       "\"ruby-bundler\" did not match one of the following "\
                       "values: npm, bundler")
        end
    end
  end

  context "with an invalid directory value" do
    let(:config_file_contents) do
      fixture("config_files/invalid_directory_value.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/directory' of type "\
                  "array did not match the following type: string")
        end
    end
  end

  context "with an invalid exclude-paths value" do
    let(:config_file_contents) do
      fixture("config_files/invalid_exclude_paths_value.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/exclude-paths' of type string did not match the following type: array")
        end
    end
  end

  context "with an invalid exclude-paths array item value" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            exclude-paths:
              - 1234
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/exclude-paths/0' of type integer did not match the following type: string")
      end
    end
  end

  context "with .. in exclude_paths value" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            exclude-paths:
              - "../.."
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/exclude-paths/0' must not include '..'.")
      end
    end
  end

  context "with a time zone and cron expression" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "npm"
            directory: "/"
            schedule:
              interval: "cron"
              cronjob: "0 0 * * *"
              timezone: "America/New_York"
      YAML
    end

    it "adds the timezone to the cron expression" do
      expect(action.updates.first["update-schedule-cron-expression"]).to eq("0 0 * * * America/New_York")
    end
  end

  context "with a cron schedule and no timezone" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "npm"
            directory: "/"
            schedule:
              interval: "cron"
              cronjob: "0 0 * * *"
      YAML
    end

    it "adds the timezone to the cron expression" do
      expect(action.updates.first["update-schedule-cron-expression"]).to eq("0 0 * * * UTC")
    end
  end

  context "with `include` for commit messages but no prefix" do
    let(:config_file_contents) do
      fixture("config_files/invalid_commit_message_option.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/commit-message' has a "\
                  "property 'include' that depends on a missing "\
                  "property 'prefix'")
        end
    end
  end

  context "missing a required key" do
    let(:config_file_contents) do
      fixture("config_files/missing_required_key.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0' did not contain a "\
                  "required property of 'schedule'")
        end
    end
  end

  context "with invalid optional values" do
    let(:config_file_contents) do
      fixture("config_files/invalid_optional_values.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).to eq(
            "The property '#/updates/0/allow/0' "\
            "contains additional properties [\"update-type\"] outside of "\
            "the schema when none are allowed\n"\
            "The property '#/updates/0/allow/1' did "\
            "not contain a minimum number of properties 1\n"\
            "The property '#/updates/0/allow/2' "\
            "contains additional properties [\"rogue_key\"] outside of the "\
            "schema when none are allowed\n"\
            "The property '#/updates/0/ignore/0' did "\
            "not contain a required property of 'dependency-name'\n"\
            "The property '#/updates/0/ignore/1' "\
            "contains additional properties [\"rogue_key\"] outside of the "\
            "schema when none are allowed\n"\
            "The property '#/updates/1/versioning-strategy' "\
            "value \"widen\" did not match one of the following values:"\
            " lockfile-only, auto, increase, increase-if-necessary\n"\
            "The property '#/updates/1/reviewers/1' of type "\
            "integer did not match the following type: string",
          )
        end
    end
  end

  context "with ignore condition specifying semver update types" do
    let(:config_file_contents) do
      fixture("config_files/minimal_with_ignored_update_types.yml")
    end

    it "returns ignore conditions including specified update types" do
      expect(action.updates.length).to eq(1)
      expect(action.updates.first["ignore-conditions"]).to eq([
                                                                {
                                                                  "dependency_name" => "rspec",
                                                                  "update_types" => ["version-update:semver-patch"],
                                                                  "version_requirement" => nil,
                                                                },
                                                                {
                                                                  "dependency_name" => "rails",
                                                                  "update_types" => nil,
                                                                  "version_requirement" => ">= 0",
                                                                },

                                                              ])
    end
  end

  context "with .. in the directory" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "../.."
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/directory' must not include '..'")
      end
    end
  end

  context "with ignore condition specifying a mix of semver update types and version requirements for a dependency" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
              versions: ["4.x", "5.x"]
              update-types: ["version-update:semver-patch", "version-update:semver-minor"]
      YAML
    end

    it "returns an ignore condition for all semver update types and an ignore condition for each version requirement" do
      expect(action.updates.length).to eq(1)
      expect(action.updates.first["ignore-conditions"]).to eq([
                                                                {
                                                                  "dependency_name" => "rails",
                                                                  "update_types" => nil,
                                                                  "version_requirement" => "4.x",
                                                                },
                                                                {
                                                                  "dependency_name" => "rails",
                                                                  "update_types" => nil,
                                                                  "version_requirement" => "5.x",
                                                                },
                                                                {
                                                                  "dependency_name" => "rails",
                                                                  "update_types" => ["version-update:semver-patch",
                                                                                     "version-update:semver-minor",],
                                                                  "version_requirement" => nil,
                                                                },
                                                              ])
    end
  end

  context "with an invalid ignore condition update-types value" do
    let(:config_file_contents) do
      valid = fixture("config_files/minimal_with_ignored_update_types.yml")
      valid.sub('update-types: ["version-update:semver-patch"]', 'update-types: ["some-invalid-value"]')
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("value \"some-invalid-value\" did not match one of the following values: " \
            "version-update:semver-major, version-update:semver-minor, version-update:semver-patch")
      end
    end
  end

  context "with an invalid ignore condition version requirement" do
    let(:config_file_contents) do
      fixture("config_files/invalid_ignore_requirement.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/ignore/0/versions' includes "\
                  "invalid version requirements for a bundler ignore condition")
        end
    end
  end

  context "with too many update config entries" do
    let(:config_file_contents) { fixture("config_files/too_many.yml") }

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates' had more items than the "\
                  "allowed 200")
        end
    end
  end

  context "with an excessive number of errors" do
    let(:config_file_contents) { fixture("config_files/excessive_errors.yml") }

    it "truncates to the first 50 error messages" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)

          individual_errors = error.message.split("\n")

          expect(individual_errors.length).to be(51)
          expect(individual_errors.last).to eql("and 2 more errors.")
        end
    end
  end

  context "missing a invalid additional key" do
    let(:config_file_contents) do
      fixture("config_files/invalid_additional_key.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/' contains additional "\
                  "properties [\"branch\"] outside of the schema when none "\
                  "are allowed")
        end
    end
  end

  context "with deprecated automerge updates" do
    let(:config_file_contents) do
      fixture("config_files/deprecated_automerged_updates.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/' contains additional "\
                  "properties [\"automerged_updates\"] outside of the schema "\
                  "when none are allowed")
        end
    end
  end

  context "with deprecated live updates" do
    let(:config_file_contents) do
      fixture("config_files/deprecated_live_updates.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to start_with("The property '#/updates/0/schedule/interval'"\
                          " value \"live\" did not match")
        end
    end
  end

  context "with duplicate update configs" do
    let(:config_file_contents) do
      fixture("config_files/duplicate.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("Update configs must have a unique combination of 'package-ecosystem', " \
                  "'directory', and 'target-branch'. Ecosystem 'bundler' has overlapping directories.")
        end
    end
  end

  context "when a glob is used" do
    let(:config_file_contents) do
      fixture("config_files/globs.yml")
    end

    it "doesn't raise an error" do
      expect { action.updates }.not_to raise_error
    end
  end

  context "when a glob is used with a directory" do
    let(:config_file_contents) do
      fixture("config_files/globs_directory.yml")
    end

    it "raises an error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/directory' must not include a glob pattern")
        end
    end
  end

  context "when there's a glob in two UpdateConfigs and they overlap" do
    let(:config_file_contents) do
      fixture("config_files/globs_multiple.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("Update configs must have a unique combination of 'package-ecosystem', 'directory', and " \
                  "'target-branch'. Dependabot cannot determine if 'bundler' has overlapping directories.")
        end
    end
  end

  context "when there's a glob in two UpdateConfigs and they dont' overlap" do
    let(:config_file_contents) do
      fixture("config_files/globs_multiple_no_overlap.yml")
    end

    it "doesn't raise an error" do
      expect { action.updates }.not_to raise_error
    end
  end

  context "when a glob overlaps with another directory in the same ecosystem and target-branch" do
    let(:config_file_contents) do
      fixture("config_files/globs_overlap.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("Update configs must have a unique combination of 'package-ecosystem', " \
                  "'directory', and 'target-branch'. Ecosystem 'bundler' has overlapping directories.")
        end
    end
  end

  context "with an invalid schedule time" do
    let(:config_file_contents) do
      fixture("config_files/invalid_schedule_time.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/schedule/time' value "\
                "\"2018-11-13T20:20:39+00:00\" did not match the regex "\
                "'^\\d\\d:\\d\\d$'")
      end
    end
  end

  context "with an invalid schedule day" do
    let(:config_file_contents) do
      fixture("config_files/invalid_schedule_day.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/schedule/day' value "\
                "\"invalid day\" did not match one of the following values: "\
                "monday, tuesday, wednesday, thursday, friday, saturday, "\
                "sunday")
      end
    end
  end

  context "with an invalid schedule timezone" do
    let(:config_file_contents) do
      fixture("config_files/invalid_schedule_timezone.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/schedule/timezone' value "\
                "\"invalid timezone\" is not a valid timezone.")
      end
    end
  end

  context "with an invalid branch name separator" do
    let(:config_file_contents) do
      fixture("config_files/invalid_branch_name_separator.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/updates/0/pull-request-branch-name/separator' "\
            "value \"@\" did not match one of the following "\
            "values: -, /, _"
          )
      end
    end
  end

  context "with a nuget ignored range" do
    let(:config_file_contents) do
      fixture("config_files/nuget_ignored_version_range.yml")
    end

    it "correctly ignores the range" do
      parsed_config = action.updates

      expect(parsed_config.first["ignore-conditions"]).to eq(
        [{
          "dependency_name" => "CommandLineParser\\",
          "update_types" => nil,
          "version_requirement" => "(,2.0)",
        }]
      )
    end
  end

  context "configuring vendoring for an unsupported ecosystem" do
    let(:config_file_contents) do
      fixture("config_files/npm_with_vendoring.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/updates/0/' contains additional properties "\
            "[\"vendor\"] outside of the schema when none are allowed"
          )
      end
    end
  end

  context "fetches 'cronjob' property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/with_cronjob.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        not_to raise_error
    end
  end

  context "fetches 'quarterly' schedule property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/with_quarterly_schedule.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        not_to raise_error
    end
  end

  context "fetches 'semiannually' schedule property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/with_semiannually_schedule.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        not_to raise_error
    end
  end

  context "fetches 'yearly' schedule property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/with_yearly_schedule.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        not_to raise_error
    end
  end

  context "fetches invalid schedule property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/with_invalid_schedule.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("The property '#/updates/0/schedule/interval' value "\
                  "\"biweekly\" did not match one of the following values: "\
                  "daily, weekly, monthly, quarterly, semiannually, yearly, cron")
        end
    end
  end

  context "fetches interval with missing 'cronjob' property from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/missing_cronjob_property.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/updates/0/interval' must include 'cronjob' property if interval type is 'cron'"
          )
      end
    end
  end

  context "with invalid 'cronjob' property parsed from yaml file" do
    let(:config_file_contents) do
      fixture("config_files/invalid_cronjob_property.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/updates/0/schedule/interval/cronjob' is invalid: Invalid cronjob expression:"
          )
      end
    end
  end

  context "with 'cronjob' property that is less than 24 hours" do
    let(:config_file_contents) do
      fixture("config_files/with_cronjob_less_than_min_allowed.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/schedule/interval/cronjob' is invalid: " \
                "Cronjob expression 'every 5 hours' has a minimum interval of 4 hours " \
                "which is less than the minimum allowed interval of 24 hours.")
      end
    end
  end

  context "with 'cronjob' property that is more than 1 year" do
    let(:config_file_contents) do
      fixture("config_files/with_cronjob_more_than_max_allowed.yml")
    end

    it "raises a helpful error" do
      # Feb 29 only occurs in leap years, so max interval can be ~4 years
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to eq("The property '#/updates/0/schedule/interval/cronjob' is invalid: " \
                "Cronjob expression '0 0 29 2 *' has a maximum interval of 35064 hours " \
                "which is greater than the maximum allowed interval of 8765 hours (1 year).")
      end
    end
  end

  context "with an invalid insecure-external-code-execution value" do
    let(:config_file_contents) do
      valid = fixture("config_files/bundler_with_registry_with_code_execution_allowed.yml")
      valid.gsub("insecure-external-code-execution: allow", "insecure-external-code-execution: some-invalid-value")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include('value "some-invalid-value" did not match one of the following values: allow, deny')
      end
    end
  end

  context "configuring insecure-external-code-execution for an unsupported ecosystem" do
    let(:config_file_contents) do
      fixture("config_files/npm_with_external_code_execution.yml")
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/updates/0/' contains additional properties "\
            "[\"insecure-external-code-execution\"] outside of the schema when none are allowed"
          )
      end
    end
  end

  context "with a valid composer-repository" do
    let(:config_file_contents) { fixture("config_files/composer_with_repository.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "composer-acme" => {
                  "type" => "composer_repository",
                  "url" => "repo.packagist.com/acme-company",
                  "username" => "acme",
                  "password" => "${{secrets.MY_PACKAGIST_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid docker-registry" do
    let(:config_file_contents) { fixture("config_files/docker_with_registry.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "docker-acme" => {
                  "type" => "docker_registry",
                  "url" => "ghcr.io",
                  "username" => "acme",
                  "password" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                  "replaces-base" => true,
                },
              })
    end
  end

  context "with a valid helm-registry" do
    let(:config_file_contents) { fixture("config_files/helm_with_registry.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "docker-acme" => {
                  "type" => "helm_registry",
                  "url" => "ghcr.io",
                  "username" => "acme",
                  "password" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                  "replaces-base" => true,
                },
              })
    end
  end

  context "with a valid terraform registry" do
    let(:config_file_contents) { fixture("config_files/terraform_with_registry.yml") }

    it "returns registries" do
      expect(action.registries).to eq({
                                        "terraform-example" => {
                                          "type" => "terraform_registry",
                                          "url" => "registry.terraform.example.org",
                                          "token" => "${{secrets.MY_TERRAFORM_TOKEN}}",
                                        },
                                      })
    end
  end

  context "with a valid git registry" do
    let(:config_file_contents) { fixture("config_files/gomod_with_gitsource.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "git_source",
                  "url" => "https://github.com",
                  "username" => "x-access-token",
                  "password" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                },
              })
    end
  end

  context "with a valid git registry missing url protocol" do
    let(:config_file_contents) do
      config = fixture("config_files/gomod_with_gitsource.yml")
      config.gsub(/url:.*/, "url: github.com")
    end

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "git_source",
                  "url" => "github.com",
                  "username" => "x-access-token",
                  "password" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                },
              })
    end
  end

  context "with a valid hex-organization" do
    let(:config_file_contents) { fixture("config_files/mix_with_hex_organization.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "organization" => "acme",
                  "type" => "hex_organization",
                  "key" => "${{secrets.MY_HEX_KEY}}",
                },
              })
    end
  end

  context "with a valid hex-repository" do
    let(:config_file_contents) { fixture("config_files/mix_with_hex_repository.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "hex_repository",
                  "repo" => "my_hex_repository",
                  "url" => "https://hex.example.com",
                  "public-key-fingerprint" => "${{secrets.MY_PUBLIC_KEY_FINGERPRINT}}",
                  "auth-key" => "${{secrets.MY_HEX_KEY}}",
                },
              })
    end
  end

  context "with a valid maven-repository" do
    let(:config_file_contents) { fixture("config_files/maven_with_repository.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "maven-acme" => {
                  "type" => "maven_repository",
                  "url" => "https://artifactory.acme.com",
                  "username" => "acme",
                  "password" => "${{secrets.MY_ARTIFACTORY_PASSWORD}}",
                  "replaces-base" => true,
                },
              })
    end

    context "with no credentials" do
      let(:config_file_contents) { fixture("config_files/maven_with_repository_no_creds.yml") }

      it "returns registries" do
        expect(action.registries).
          to eq({
                  "maven-acme" => {
                    "type" => "maven_repository",
                    "url" => "https://artifactory.acme.com",
                    "replaces-base" => true,
                  },
                })
      end
    end
  end

  context "with a valid gradle maven-repository" do
    let(:config_file_contents) { fixture("config_files/gradle_with_repository.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "maven-acme" => {
                  "type" => "maven_repository",
                  "url" => "https://artifactory.acme.com",
                  "username" => "acme",
                  "password" => "${{secrets.MY_ARTIFACTORY_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid token npm-registry" do
    let(:config_file_contents) { fixture("config_files/npm_with_registry.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "npm-acme" => {
                  "type" => "npm_registry",
                  "url" => "registry.npmjs.org",
                  "token" => "${{secrets.MY_NPM_TOKEN}}",
                  "replaces-base" => true,
                },
              })
    end
  end

  context "with a valid username+password npm-registry" do
    let(:config_file_contents) { fixture("config_files/npm_with_registry_username.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "npm-acme" => {
                  "type" => "npm_registry",
                  "url" => "registry.npmjs.org",
                  "username" => "acme",
                  "password" => "${{secrets.MY_NPM_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid nuget-feed" do
    let(:config_file_contents) { fixture("config_files/nuget_with_feed.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "nuget-azp-acme" => {
                  "type" => "nuget_feed",
                  "url" => "https://pkgs.dev.azure.com/microsoftLearnModule/" \
                           "aa398e8e-b4d1-11ea-b3de-0242ac130004/_packaging/My_Feed/nuget/v3/index.json",
                  "token" => "${{secrets.MY_AZURE_DEVOPS_TOKEN}}",
                },
              })
    end
  end

  context "with a valid username+password nuget-feed" do
    let(:config_file_contents) { fixture("config_files/nuget_with_feed_username.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "nuget-azp-acme" => {
                  "type" => "nuget_feed",
                  "url" => "https://pkgs.dev.azure.com/microsoftLearnModule/" \
                           "aa398e8e-b4d1-11ea-b3de-0242ac130004/_packaging/My_Feed/nuget/v3/index.json",
                  "username" => "microsoftLearnModule",
                  "password" => "${{secrets.MY_AZURE_DEVOPS_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid public nuget-feed" do
    let(:config_file_contents) { fixture("config_files/nuget_with_public_feed.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "nuget-azp-acme" => {
                  "type" => "nuget_feed",
                  "url" => "https://pkgs.dev.azure.com/microsoftLearnModule/" \
                           "aa398e8e-b4d1-11ea-b3de-0242ac130004/_packaging/My_Feed/nuget/v3/index.json",
                  "token" => "${{secrets.MY_AZURE_DEVOPS_TOKEN}}",
                },
                "public" => {
                  "type" => "nuget_feed",
                  "url" => "https://api.nuget.org/v3/index.json",
                },
              })
    end
  end

  context "with a valid pub-repository" do
    let(:config_file_contents) { fixture("config_files/pub_with_pub_repository.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "pub_repository",
                  "url" => "https://pub.example.com/path",
                  "token" => "${{secrets.MY_PUB_TOKEN}}",
                },
              })
    end
  end

  context "with a valid cargo-registry" do
    let(:config_file_contents) { fixture("config_files/cargo_with_cargo_registry.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "cargo_registry",
                  "registry" => "cargo-registry-name",
                  "url" => "https://cargo.example.com/path",
                  "token" => "${{secrets.MY_CARGO_TOKEN}}",
                },
              })
    end
  end

  context "with a valid go-proxy" do
    let(:config_file_contents) { fixture("config_files/gomod_with_go_proxy.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "jfrog-goproxy" => {
                  "type" => "goproxy_server",
                  "url" => "https://company.jfrog.io/artifactory/api/go/go-virtual",
                  "username" => "${{secrets.JFROG_USERNAME}}",
                  "password" => "${{secrets.JFROG_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid python-index" do
    let(:config_file_contents) { fixture("config_files/python_with_index.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "python-azp-acme" => {
                  "type" => "python_index",
                  "url" => "https://pkgs.dev.azure.com/acme/_packaging/my-awesome-feed/pypi/simple",
                  "token" => "${{secrets.MY_AZURE_DEVOPS_TOKEN}}",
                  "replaces-base" => true,
                },
              })
    end
  end

  context "with a valid username+password python-index" do
    let(:config_file_contents) { fixture("config_files/python_with_index_username.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "python-azp-acme" => {
                  "type" => "python_index",
                  "url" => "https://pkgs.dev.azure.com/acme/_packaging/my-awesome-feed/pypi/simple",
                  "username" => "python-mcpyface",
                  "password" => "${{secrets.MY_AZURE_DEVOPS_PASSWORD}}",
                },
              })
    end
  end

  context "with a valid rubygems-server" do
    let(:config_file_contents) { fixture("config_files/bundler_with_gemserver.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "ruby-ghp" => {
                  "type" => "rubygems_server",
                  "url" => "https://rubygems.pkg.github.com/acme/github_api",
                  "token" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                  "replaces-base" => true,
                },
              })
    end
  end

  context "with a valid username+password rubygems-server" do
    let(:config_file_contents) { fixture("config_files/bundler_with_gemserver_username.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "ruby-acme" => {
                  "type" => "rubygems_server",
                  "url" => "https://acme.com/rubygems",
                  "username" => "acme",
                  "password" => "${{secrets.MY_BASIC_AUTH_PASSWORD}}",
                },
              })
    end
  end

  context "with multiple registries" do
    let(:config_file_contents) { fixture("config_files/npm_with_registries.yml") }

    it "returns registries" do
      expect(action.registries).
        to eq({
                "github-acme" => {
                  "type" => "git_source",
                  "url" => "github.com",
                  "username" => "x-access-token",
                  "password" => "${{secrets.MY_GITHUB_PERSONAL_TOKEN}}",
                },
                "npm-acme-cache" => {
                  "type" => "npm_registry",
                  "url" => "artifactory.acme.com/artifactory/api/npm/npm-stable-and-cache",
                  "token" => "${{secrets.MY_ARTIFACTORY_TOKEN}}",
                },
                "npm-acme" => {
                  "type" => "npm_registry",
                  "url" => "artifactory.acme.com/artifactory/api/npm/npm-stable",
                  "token" => "${{secrets.MY_ARTIFACTORY_TOKEN}}",
                },
              })
    end

    it "returns wildcard key" do
      time_of_day = repo.default_update_schedule_time_of_day
      hour, min = time_of_day.split(":").map(&:to_i)

      expect(action.updates).
        to eq([{
                "allowed-updates" => [{ "dependency_type" => "direct", "update_type" => "all" }],
                "commit-message-include-scope" => nil,
                "commit-message-prefix" => nil,
                "commit-message-prefix-development" => nil,
                "cooldown" => nil,
                "custom-labels" => nil,
                "default-assignees" => nil,
                "default-milestone" => nil,
                "default-reviewers" => nil,
                "directory" => "/.",
                "enable-beta-ecosystems" => false,
                "ignore-conditions" => nil,
                "lockfile-only" => false,
                "open-pull-requests-limit" => nil,
                "package-manager" => "npm_and_yarn",
                "pull-request-branch-name-separator" => nil,
                "rebase-strategy" => nil,
                "registries" => "*",
                "requirements-update-strategy" => nil,
                "target-branch" => nil,
                "update-schedule" => "daily",
                "update-schedule-day-of-week" => nil,
                "update-schedule-time-of-day" => time_of_day,
                "update-schedule-timezone" => "UTC",
                "vendor" => false,
                "insecure-external-code-execution" => nil,
                "groups" => nil,
                "update-schedule-cron-expression" => "#{min} #{hour} * * 1-5 UTC",
                "multi_ecosystem_config_id" => nil,
                "multi_ecosystem_config_name" => nil,
                "multi_ecosystem_config_patterns" => nil,
                "exclude-paths" => nil,
              }])
    end
  end

  context "with a invalid registry type" do
    let(:config_file_contents) do
      valid = fixture("config_files/npm_with_registry.yml")
      valid.gsub("type: npm-registry", "type: invalid-type")
    end

    it "raises a helpful error" do
      expect { action.registries }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/registries/npm-acme/type' value \"invalid-type\" did not "\
            "match one of the following "
          )
      end
    end
  end

  context "with a invalid npm-registry" do
    let(:config_file_contents) do
      valid = fixture("config_files/npm_with_registry.yml")
      valid.gsub(/.*token: .*/, "")
    end

    it "raises a helpful error" do
      expect { action.registries }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The property '#/registries/npm-acme/' of type object did not match one or more of the required schemas"
          )
      end
    end
  end

  context "with a registry name that is too long" do
    let(:config_file_contents) do
      valid = fixture("config_files/npm_with_registry.yml")
      valid.gsub(/npm-acme/, "name-that-is-too-long-so-it-should-fail-to-validate-and-then-raise")
    end

    it "raises a helpful error" do
      expect { action.registries }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with(
            "The registry name 'name-that-is-too-long-so-it-should-fail-to-validate-and-then-raise' is too long." \
            " The maximum is 64 characters."
          )
      end
    end
  end

  context "with an update config that references an undefined registry" do
    let(:config_file_contents) { fixture("config_files/invalid_registry_name.yml") }

    it "raises a helpful error" do
      expect { action.registries }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to start_with("The property '#/updates/0/registries' includes the \"nonexistent-registry\" registry")
      end
    end
  end

  context "with an update config that references a registry but no registries are defined" do
    let(:config_file_contents) { fixture("config_files/missing_registries.yml") }

    it "raises a helpful error" do
      expect { action.registries }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("The property '#/updates/0/registries' includes the \"nonexistent-registry-1\" registry")
        expect(error.message).
          to include("The property '#/updates/0/registries' includes the \"nonexistent-registry-2\" registry")
      end
    end
  end

  context "when there is an ignore condition that specifies duplicate version requirements" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
              versions: ["4.x", "4.x"]
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("The property '#/updates/0/ignore/0/versions' includes a duplicate. "\
                     "Ignores must have a unique combination of 'dependency-name' and 'versions'")
      end
    end
  end

  context "when there is a single ignore condition that specifies duplicate update types" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
              update-types: ["version-update:semver-patch", "version-update:semver-patch"]
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("The property '#/updates/0/ignore/0/update-types' includes a duplicate. "\
                     "Ignores must have a unique combination of 'dependency-name' and 'update-types'")
      end
    end
  end

  context "when there are multiple ignore conditions that specifies duplicate update types for a single dependency" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
              update-types: ["version-update:semver-patch"]
            - dependency-name: "rails"
              update-types: ["version-update:semver-patch"]
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("The property '#/updates/0/ignore/1/update-types' includes a duplicate. "\
                     "Ignores must have a unique combination of 'dependency-name' and 'update-types'")
      end
    end
  end

  context "when there are multiple ignore conditions that specifies duplicate dependency names with versions" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
              versions: ["1.2", "3.0"]
            - dependency-name: "rails"
              versions: ["2.2"]
            - dependency-name: "rails"
              update-types: ["version-update:semver-patch"]
            - dependency-name: "rails"
      YAML
    end

    it "does not raise" do
      expect { action.updates }.not_to raise_error
    end
  end

  context "when there are multiple ignore conditions that specifies duplicate dependency names matching all versions" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
            - dependency-name: "rails"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
        expect(error.class).to eq(described_class::Invalid)
        expect(error.message).
          to include("The property '#/updates/0/ignore/1/dependency-name' is a duplicate.")
      end
    end
  end

  context "when there are multiple ignore conditions that specifies duplicate dependency names in different configs" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
          - package-ecosystem: "bundler"
            directory: "/other"
            schedule:
              interval: "daily"
            ignore:
            - dependency-name: "rails"
      YAML
    end

    it "does not raise" do
      expect { action.updates }.not_to raise_error
    end
  end

  context "with an unused registry" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        registries:
          npm-acme-cache:
            type: npm-registry
            url: artifactory.acme.com/artifactory/api/npm/npm-stable-and-cache
            token: ${{secrets.MY_ARTIFACTORY_TOKEN}}
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.to raise_error(described_class::Invalid) do |error|
        expect(error.message).
          to include("The property '#/registries' includes the \"npm-acme-cache\" registry which is not used")
      end
    end
  end

  context "when a wildcard registry is specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        registries:
          npm-acme-cache:
            type: npm-registry
            url: artifactory.acme.com/artifactory/api/npm/npm-stable-and-cache
            token: ${{secrets.MY_ARTIFACTORY_TOKEN}}
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
            registries: "*"
      YAML
    end

    it "does not raise" do
      expect { action.updates }.not_to raise_error
    end
  end

  context "when multiple directories are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directories:
              - "/app"
              - "/stuff"
            schedule:
              interval: "daily"
      YAML
    end

    it "creates a multi-directory update config" do
      expect(action.updates.first["directories"]).to match_array(["/app", "/stuff"])
      expect(action.updates.first["directory"]).to be_nil
    end
  end

  context "when both a directory and directories are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/app"
            directories:
              - "/stuff"
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error(described_class::Invalid,
                       %r{The property '#/updates/0/directories' must not be used with 'directory'})
    end
  end

  context "when neither a directory nor directories are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error(described_class::Invalid,
                       %r{The property '#/updates/0' of type object did not match one or more of the required schemas})
    end
  end

  context "when two single directory update configs in the same ecosystem are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
          - package-ecosystem: "bundler"
            directory: "/other"
            schedule:
              interval: "daily"
      YAML
    end

    it "returns two single-directory update configs" do
      expect(action.updates.count).to eq(2)
      expect(action.updates.first["directory"]).to eq("/.")
      expect(action.updates.last["directory"]).to eq("/other")
    end
  end

  context "when two multi-directory update configs in the same ecosystem are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directories:
              - "/app"
              - "/stuff"
            schedule:
              interval: "daily"
          - package-ecosystem: "bundler"
            directories:
              - "/other"
              - "/things"
            schedule:
              interval: "daily"
      YAML
    end

    it "returns two multi-directory update configs" do
      expect(action.updates.count).to eq(2)
      expect(action.updates.first["directories"]).to match_array(["/app", "/stuff"])
      expect(action.updates.last["directories"]).to match_array(["/other", "/things"])
    end
  end

  context "when a single directory and a multi-directory update config in the same ecosystem are specified" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            schedule:
              interval: "daily"
          - package-ecosystem: "bundler"
            directories:
              - "/."
              - "/stuff"
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("Update configs must have a unique combination of 'package-ecosystem', 'directory', " \
                  "and 'target-branch'. Ecosystem 'bundler' has overlapping directories.")
        end
    end
  end

  context "with duplicate update configs that need to be cleaned" do
    let(:config_file_contents) do
      <<~YAML
        version: 2
        updates:
          - package-ecosystem: "bundler"
            directory: "/foo/"
            schedule:
              interval: "daily"
          - package-ecosystem: "bundler"
            directory: "/foo"
            schedule:
              interval: "daily"
      YAML
    end

    it "raises a helpful error" do
      expect { action.updates }.
        to raise_error do |error|
          expect(error.class).to eq(described_class::Invalid)
          expect(error.message).
            to eq("Update configs must have a unique combination of 'package-ecosystem', 'directory', " \
                  "and 'target-branch'. Ecosystem 'bundler' has overlapping directories.")
        end
    end
  end

  cooldown_package_managers = %i(
    bundler
    npm
    bun
    pip
    uv
    conda
    cargo
    gomod
    composer
    maven
    gradle
    nuget
    dotnet-sdk
    swift
    pub
    elm
  )

  cooldown_non_semver_package_managers = %i(
    docker
    docker-compose
    gitsubmodule
    github_actions
    devcontainers
    helm
    terraform
    bazel
    opentofu
  )

  context "with cooldown feature" do
    cooldown_package_managers.each do |ecosystem|
      context "for #{ecosystem}" do
        context "when beta ecosystems are enabled" do
          let(:config_file_contents) do
            <<~YAML
              version: 2
              enable-beta-ecosystems: true
              updates:
                - package-ecosystem: "#{ecosystem}"
                  directory: "/"
                  schedule:
                    interval: "daily"
                  cooldown:
                    default-days: 5
            YAML
          end

          it "allows cooldown settings when beta ecosystems are enabled" do
            cooldown = action.updates.first["cooldown"]
            expect(cooldown).to eq(
              {
                "default-days" => 5,
                "semver-major-days" => 0,
                "semver-minor-days" => 0,
                "semver-patch-days" => 0,
                "include" => [],
                "exclude" => [],
              }
            )
          end
        end

        unless cooldown_non_semver_package_managers.include?(ecosystem)
          context "when cooldown is fully specified" do
            let(:config_file_contents) do
              <<~YAML
                version: 2
                enable-beta-ecosystems: true
                updates:
                  - package-ecosystem: "#{ecosystem}"
                    directory: "/"
                    schedule:
                      interval: "daily"
                    cooldown:
                      default-days: 5
                      semver-major-days: 10
                      semver-minor-days: 3
                      semver-patch-days: 1
                      include:
                        - "pytorch"
                        - "tensorflow"
                        - "dependabot*"
                      exclude:
                        - "keras"
              YAML
            end

            it "parses cooldown settings correctly" do
              cooldown = action.updates.first["cooldown"]
              expect(cooldown).to eq(
                {
                  "default-days" => 5,
                  "semver-major-days" => 10,
                  "semver-minor-days" => 3,
                  "semver-patch-days" => 1,
                  "include" => %w(pytorch tensorflow dependabot*),
                  "exclude" => ["keras"],
                }
              )
            end
          end
        end

        context "when cooldown is missing" do
          let(:config_file_contents) do
            <<~YAML
              version: 2
              enable-beta-ecosystems: true
              updates:
                - package-ecosystem: "#{ecosystem}"
                  directory: "/"
                  schedule:
                    interval: "daily"
            YAML
          end

          it "defaults cooldown to nil" do
            expect(action.updates.first["cooldown"]).to be_nil
          end
        end

        context "when cooldown is partially specified" do
          let(:config_file_contents) do
            <<~YAML
              version: 2
              enable-beta-ecosystems: true
              updates:
                - package-ecosystem: "#{ecosystem}"
                  directory: "/"
                  schedule:
                    interval: "daily"
                  cooldown:
                    default-days: 3
                    include: ["pytorch", "tensorflow", "dependabot*"]
            YAML
          end

          it "parses cooldown with missing values defaulting to 0 or empty" do
            cooldown = action.updates.first["cooldown"]
            expect(cooldown).to eq(
              {
                "default-days" => 3,
                "semver-major-days" => 0,
                "semver-minor-days" => 0,
                "semver-patch-days" => 0,
                "include" => ["pytorch", "tensorflow", "dependabot*"],
                "exclude" => [],
              }
            )
          end
        end

        context "when cooldown contains invalid values" do
          context "when any cooldown fields for days contains non-integer values" do
            let(:config_file_contents) do
              <<~YAML
                version: 2
                enable-beta-ecosystems: true
                updates:
                  - package-ecosystem: "#{ecosystem}"
                    directory: "/"
                    schedule:
                      interval: "daily"
                    cooldown:
                      default-days: "five"
              YAML
            end

            it "raises a validation error" do
              expect { action.updates }.
                to raise_error(described_class::Invalid) do |error|
                  expect(error.message).to include(
                    "The property '#/updates/0/cooldown/default-days' of type "\
                    "string did not match the following type: integer"
                  )
                end
            end
          end

          context "when any cooldown fields should be >=#{ParseConfigFile::MINIMUM_COOLDOWN_DAYS}" do
            let(:config_file_contents) do
              <<~YAML
                version: 2
                enable-beta-ecosystems: true
                updates:
                  - package-ecosystem: "#{ecosystem}"
                    directory: "/"
                    schedule:
                      interval: "daily"
                    cooldown:
                      default-days: 0
              YAML
            end

            it "raises a validation error" do
              expect { action.updates }.
                to raise_error(described_class::Invalid) do |error|
                  expect(error.message).to include(
                    "The property '#/updates/0/cooldown/default-days' did not have a minimum"\
                    " value of #{ParseConfigFile::MINIMUM_COOLDOWN_DAYS}, inclusively"
                  )
                end
            end
          end

          context "when any cooldown fields should be <=#{ParseConfigFile::MAXIMUM_COOLDOWN_DAYS}" do
            let(:config_file_contents) do
              <<~YAML
                version: 2
                enable-beta-ecosystems: true
                updates:
                  - package-ecosystem: "#{ecosystem}"
                    directory: "/"
                    schedule:
                      interval: "daily"
                    cooldown:
                      default-days: 400
              YAML
            end

            it "raises a validation error" do
              expect { action.updates }.
                to raise_error(described_class::Invalid) do |error|
                  expect(error.message).to include(
                    "The property '#/updates/0/cooldown/default-days' did not have a"\
                    " maximum value of #{ParseConfigFile::MAXIMUM_COOLDOWN_DAYS}, inclusively"
                  )
                end
            end
          end

          context "when include/exclude is not an array" do
            let(:config_file_contents) do
              <<~YAML
                version: 2
                enable-beta-ecosystems: true
                updates:
                  - package-ecosystem: "#{ecosystem}"
                    directory: "/"
                    schedule:
                      interval: "daily"
                    cooldown:
                      include: "pytorch"
              YAML
            end

            it "raises a validation error" do
              expect { action.updates }.
                to raise_error(described_class::Invalid) do |error|
                  expect(error.message).to include(
                    "The property '#/updates/0/cooldown/include' of type string did not match the following type: array"
                  )
                end
            end
          end
        end
      end
    end
  end

  context "without the multi-ecosystem feature flag" do
    let(:config_file_contents) do
      <<~YAML
        version: 2

        multi-ecosystem-groups:
          test-group:
            schedule:
              interval: "daily"

        updates:
          - package-ecosystem: "bundler"
            directory: "/"
            patterns:
              - "rails*"
              - "rspec*"
            multi-ecosystem-group: "test-group"
      YAML
    end
    let(:unsupported_message) do
      "The property '#/multi-ecosystem-groups' is not supported when multi-ecosystems is not enabled."
    end

    it "raises an error" do
      expect { action.multi_ecosystem_updates }.
        to raise_error(ParseConfigFile::Invalid) do |error|
          expect(error.message).
            to eq(unsupported_message)
        end

      expect { action.multi_ecosystem_names }.
        to raise_error(ParseConfigFile::Invalid) do |error|
          expect(error.message).
            to eq(unsupported_message)
        end
    end
  end

  context "with the multi-ecosystem feature flag enabled" do
    before do
      repo.enable_feature(:multi_ecosystems)
    end

    context "with a valid multi-ecosystem-groups configuration" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            test-group:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              multi-ecosystem-group: "test-group"
              directory: "/"
              patterns:
                - "rails*"
                - "rspec*"
        YAML
      end

      it "parses the multi-ecosystem-groups configuration correctly" do
        updates = action.multi_ecosystem_updates
        expect(updates.compact.length).to eq(1)
        expect(updates.first).to include(
          "directory" => "/.",
          "package-manager" => "bundler",
          "multi_ecosystem_config_id" => nil,
          "multi_ecosystem_config_name" => "test-group",
          "multi_ecosystem_config_patterns" => ["rails*", "rspec*"],
          "update-schedule" => "daily",
        )
      end

      it "parses the multi ecosystem names correctly" do
        names = action.multi_ecosystem_names
        expect(names.length).to eq(1)
        expect(names).to include("test-group")
      end
    end

    context "with reviewers and assignees" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            test-group:
              reviewers:
                - "reviewer1"
              assignees:
                - "assignee1"
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              multi-ecosystem-group: "test-group"
              directory: "/"
              reviewers:
                - "reviewer2"
              assignees:
                - "assignee2"
              patterns:
                - "rails*"
                - "rspec*"
            - package-ecosystem: "pip"
              multi-ecosystem-group: "test-group"
              directory: "/"
              reviewers:
                - "reviewer3"
              assignees:
                - "assignee3"
              patterns:
                - "rails*"
                - "rspec*"
        YAML
      end

      it "parses the multi-ecosystem-groups configuration correctly" do
        updates = action.multi_ecosystem_updates
        expect(updates.compact.length).to eq(2)
        expect(updates.first).to include(
          "directory" => "/.",
          "package-manager" => "bundler",
          "default-reviewers" => nil,
          "default-assignees" => %w(assignee2 assignee1),
        )
        expect(updates.last).to include(
          "directory" => "/.",
          "package-manager" => "pip",
          "default-reviewers" => nil,
          "default-assignees" => %w(assignee3 assignee1),
        )
      end
    end

    context "with multiple multi-ecosystem-groups configs" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            rails-and-rspec:
              schedule:
                interval: "daily"
            npm:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              directories:
                - "/"
                - "/app"
              patterns:
                - "rails*"
                - "rspec*"
              multi-ecosystem-group: "rails-and-rspec"

            - package-ecosystem: "npm"
              directory: "/app"
              patterns:
                - "*"
              multi-ecosystem-group: "npm"
        YAML
      end

      it "parses the multi-ecosystem-groups configuration correctly" do
        updates = action.multi_ecosystem_updates
        expect(updates.length).to eq(2)
        expect(updates.first).to include(
          "directories" => ["/.", "/app"],
          "package-manager" => "bundler",
          "multi_ecosystem_config_id" => nil,
          "multi_ecosystem_config_name" => "rails-and-rspec",
          "multi_ecosystem_config_patterns" => ["rails*", "rspec*"],
          "update-schedule" => "daily",
        )
        expect(updates.second).to include(
          "directory" => "/app",
          "package-manager" => "npm_and_yarn",
          "multi_ecosystem_config_id" => nil,
          "multi_ecosystem_config_name" => "npm",
          "multi_ecosystem_config_patterns" => ["*"],
          "update-schedule" => "daily",
        )
      end

      it "parses the multi ecosystem names correctly" do
        names = action.multi_ecosystem_names
        expect(names.length).to eq(2)
        expect(names).to include("rails-and-rspec", "npm")
      end

      it "parses the multi ecosystem exclusions properly" do
        exclusions = action.multi_ecosystem_exclusions
        expect(exclusions.length).to eq(2)

        expected_bundler_root = { "dependency_name" => "rails*", "version_requirement" => ">= 0" },
                                { "dependency_name" => "rspec*", "version_requirement" => ">= 0" }
        expect(exclusions["bundler"]["/."]).to include(*expected_bundler_root)

        expected_bundler_app = { "dependency_name" => "rails*", "version_requirement" => ">= 0" },
                               { "dependency_name" => "rspec*", "version_requirement" => ">= 0" }
        expect(exclusions["bundler"]["/app"]).to include(*expected_bundler_app)

        expected_npm_app = { "dependency_name" => "*", "version_requirement" => ">= 0" }
        expect(exclusions["npm_and_yarn"]["/app"]).to include(expected_npm_app)
      end
    end

    context "with update-types in multi-ecosystem-groups" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            minor-and-patch:
              update-types:
                - "minor"
                - "patch"
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              multi-ecosystem-group: "minor-and-patch"
              directory: "/"
              patterns:
                - "rails*"
        YAML
      end

      it "parses the update-types from multi-ecosystem-groups" do
        updates = action.multi_ecosystem_updates
        expect(updates.compact.length).to eq(1)
        expect(updates.first).to include(
          "multi_ecosystem_config_update_types" => %w(minor patch),
          "multi_ecosystem_config_patterns" => ["rails*"],
        )
      end
    end

    context "with dependency-type and exclude-patterns in multi-ecosystem-groups" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            production-deps:
              dependency-type: "production"
              exclude-patterns:
                - "test*"
              schedule:
                interval: "weekly"

          updates:
            - package-ecosystem: "npm"
              multi-ecosystem-group: "production-deps"
              directory: "/"
              patterns:
                - "*"
        YAML
      end

      it "parses all group properties from multi-ecosystem-groups" do
        updates = action.multi_ecosystem_updates
        expect(updates.compact.length).to eq(1)
        expect(updates.first).to include(
          "multi_ecosystem_config_dependency_type" => "production",
          "multi_ecosystem_config_exclude_patterns" => ["test*"],
          "multi_ecosystem_config_patterns" => ["*"],
        )
      end
    end

    context "with an invalid multi-ecosystem-groups configuration" do
      context "when multi-ecosystem-groups is set" do
        context "when schedule is not set" do
          let(:config_file_contents) do
            <<~YAML
              version: 2

              multi-ecosystem-groups:
                rails-and-rspec:
                  test: "test"

              updates:
                - package-ecosystem: "bundler"
                  patterns: ["*"]
                  directory: "/"
                  multi-ecosystem-group: "rails-and-rspec"
            YAML
          end

          it "raises an error for missing required schedule" do
            expect { action.updates }.
              to raise_error(ParseConfigFile::Invalid) do |error|
                expect(error.message).
                  to include("The group 'rails-and-rspec' must include a 'schedule' property.")
              end
          end
        end

        context "when multi-ecosystem-groups pattern is not set" do
          let(:config_file_contents) do
            <<~YAML
              version: 2

              multi-ecosystem-groups:
                rails-and-rspec:
                  schedule:
                    interval: "daily"

              updates:
                - package-ecosystem: "bundler"
                  directory: "/"
                  multi-ecosystem-group: "rails-and-rspec"
            YAML
          end

          it "raises an error for missing required patterns" do
            expect { action.updates }.
              to raise_error(ParseConfigFile::Invalid) do |error|
                expect(error.message).
                  to include("The property '#/updates/0/patterns' is required when 'multi-ecosystem-group'" \
                  " is set.")
              end
          end
        end
      end
    end

    context "with a valid package-ecosystems configuration with multiple package-ecosystems" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            rails-and-rspec:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              patterns:
                - "rails*"
                - "rspec*"
              multi-ecosystem-group: "rails-and-rspec"
            - package-ecosystem: "npm"
              directory: "/app"
              patterns:
                - "*"
              multi-ecosystem-group: "rails-and-rspec"
        YAML
      end

      it "parses the package-ecosystems configuration correctly" do
        updates = action.multi_ecosystem_updates
        expect(updates.length).to eq(2)
        expect(updates.first).to include(
          "directory" => "/.",
          "package-manager" => "bundler",
          "multi_ecosystem_config_id" => nil,
          "multi_ecosystem_config_name" => "rails-and-rspec",
          "multi_ecosystem_config_patterns" => ["rails*", "rspec*"],
          "update-schedule" => "daily",
        )
        expect(updates.second).to include(
          "directory" => "/app",
          "package-manager" => "npm_and_yarn",
          "multi_ecosystem_config_id" => nil,
          "multi_ecosystem_config_name" => "rails-and-rspec",
          "multi_ecosystem_config_patterns" => ["*"],
          "update-schedule" => "daily",
        )
      end
    end

    context "with both multi-ecosystem-groups and standalone package-ecosystem set" do
      let(:config_file_contents) do
        <<~YAML
          version: 2

          multi-ecosystem-groups:
            irrelevant:
              schedule:
                interval: "daily"

          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
            - package-ecosystem: "npm"
              directory: "/app"
              patterns: ["*"]
              multi-ecosystem-group: "irrelevant"
        YAML
      end

      it "does not raise an error" do
        expect { action.updates }.not_to raise_error
      end
    end

    context "when a group is not a Hash" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          multi-ecosystem-groups:
            not-a-hash: "string"
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "raises an error about group not being an object" do
        expect { action.updates }.
          to raise_error(ParseConfigFile::Invalid) do |error|
          expect(error.message).to include("must be an object")
        end
      end
    end

    context "when a group is missing schedule" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          multi-ecosystem-groups:
            missing-schedule: {}
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              schedule:
                interval: "daily"
        YAML
      end

      it "raises an error about missing schedule" do
        expect { action.updates }.

          to raise_error(ParseConfigFile::Invalid) do |error|
          expect(error.message).to include("must include a 'schedule' property")
        end
      end
    end

    context "when an update references a non-existent group" do
      let(:config_file_contents) do
        <<~YAML
          version: 2
          multi-ecosystem-groups:
            valid-group:
              schedule:
                interval: "daily"
          updates:
            - package-ecosystem: "bundler"
              directory: "/"
              multi-ecosystem-group: "not-a-group"
              patterns: ["*"]
        YAML
      end

      it "raises an error about undefined group" do
        expect { action.updates }.
          to raise_error(ParseConfigFile::Invalid) do |error|
          expect(error.message).to include("is not defined in multi-ecosystem-groups")
        end
      end
    end

    context "when milestone is set on multi-ecosystem update" do
      context "when milestone is set on a update" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
                milestone: 1
          YAML
        end

        it "raises an error" do
          expect { action.updates }.
            to raise_error(ParseConfigFile::Invalid) do |error|
            expect(error.message).to eq(
              "\"milestone\" should only be set on the associated multi-ecosystem group, "\
              "not directly on updates that are part of a multi-ecosystem update group."
            )
          end
        end
      end

      context "when milestone is set on a multi-ecosystem group" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
                milestone: 1

            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
          YAML
        end

        it "sets a milestone on updates" do
          updates = action.multi_ecosystem_updates
          expect(updates.first).to include(
            "directory" => "/.",
            "multi_ecosystem_config_name" => "valid-group",
            "default-milestone" => 1,
          )
        end
      end
    end

    context "when target-branch is set on multi-ecosystem update" do
      context "when milestone is set on a update" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
                target-branch: "dev"
          YAML
        end

        it "raises an error" do
          expect { action.updates }.
            to raise_error(ParseConfigFile::Invalid) do |error|
            expect(error.message).to eq(
              "\"target-branch\" should only be set on the associated multi-ecosystem group, "\
              "not directly on updates that are part of a multi-ecosystem update group."
            )
          end
        end
      end

      context "when target-branch is set on a multi-ecosystem group" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
                target-branch: "dev"

            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
          YAML
        end

        it "sets a milestone on updates" do
          updates = action.multi_ecosystem_updates
          expect(updates.first).to include(
            "directory" => "/.",
            "multi_ecosystem_config_name" => "valid-group",
            "target-branch" => "dev",
          )
        end
      end
    end

    context "when open-pull-requests-limit is set on multi-ecosystem update" do
      context "when open-pull-requests-limit is set on a update" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
                open-pull-requests-limit: 5
          YAML
        end

        it "raises an error" do
          expect { action.updates }.
            to raise_error(ParseConfigFile::Invalid) do |error|
            expect(error.message).to eq(
              "\"open-pull-requests-limit\" should only be set on the associated multi-ecosystem group, "\
              "not directly on updates that are part of a multi-ecosystem update group."
            )
          end
        end
      end

      context "when open-pull-requests-limit is set on a multi-ecosystem group" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
                open-pull-requests-limit: 5

            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
          YAML
        end

        it "sets a milestone on updates" do
          updates = action.multi_ecosystem_updates
          expect(updates.first).to include(
            "directory" => "/.",
            "multi_ecosystem_config_name" => "valid-group",
            "open-pull-requests-limit" => 5,
          )
        end
      end
    end

    context "when commit-message is set on multi-ecosystem update" do
      context "when commit-message is set on a update" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
                commit-message:
                  prefix: "fix"
          YAML
        end

        it "raises an error" do
          expect { action.updates }.
            to raise_error(ParseConfigFile::Invalid) do |error|
            expect(error.message).to eq(
              "\"commit-message\" should only be set on the associated multi-ecosystem group, "\
              "not directly on updates that are part of a multi-ecosystem update group."
            )
          end
        end
      end

      context "when milestone is set on a multi-ecosystem group" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
                commit-message:
                  prefix: "fix"
                  prefix-development: "dev fix"
                  include: "scope"

            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
          YAML
        end

        it "sets a milestone on updates" do
          updates = action.multi_ecosystem_updates
          expect(updates.first).to include(
            "directory" => "/.",
            "multi_ecosystem_config_name" => "valid-group",
            "commit-message-prefix" => "fix",
            "commit-message-prefix-development" => "dev fix",
            "commit-message-include-scope" => true,
          )
        end
      end
    end

    context "when pull-request-branch-name-separator is set on multi-ecosystem update" do
      context "when pull-request-branch-name-separator is set on a update" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
                pull-request-branch-name:
                  separator: "-"
          YAML
        end

        it "raises an error" do
          expect { action.updates }.
            to raise_error(ParseConfigFile::Invalid) do |error|
            expect(error.message).to eq(
              "\"pull-request-branch-name\" should only be set on the associated multi-ecosystem group, "\
              "not directly on updates that are part of a multi-ecosystem update group."
            )
          end
        end
      end

      context "when pull-request-branch-name-separator is set on a multi-ecosystem group" do
        let(:config_file_contents) do
          <<~YAML
            version: 2
            multi-ecosystem-groups:
              valid-group:
                schedule:
                  interval: "daily"
                pull-request-branch-name:
                  separator: "-"

            updates:
              - package-ecosystem: "bundler"
                directory: "/"
                multi-ecosystem-group: "valid-group"
                patterns: ["*"]
          YAML
        end

        it "sets a milestone on updates" do
          updates = action.multi_ecosystem_updates
          expect(updates.first).to include(
            "directory" => "/.",
            "multi_ecosystem_config_name" => "valid-group",
            "pull-request-branch-name-separator" => "-",
          )
        end
      end
    end
  end
end
