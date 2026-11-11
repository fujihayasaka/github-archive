# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdateJobSerializerPrivate, type: :serializer do
  include MonolithSettingsHelper
  include ProximaHelpers
  include GitHubSecurityAdvisoryHelpers

  subject(:serialized_update_job) { described_class.new(update_job) }

  let(:update_job) { FactoryBot.create(:update_job) }

  before do
    update_job.update_config.update!(all_registries: true)

    stub_proxima_repo_request(repo_id: update_job.repo.github_id, fixture: "proxima_repo")
  end

  describe "#source" do
    subject(:source) { serialized_update_job.source }

    it "returns the update_config's directory" do
      expect(source[:directory]).to eq("/")
    end

    context "when the update job has directories" do
      before { update_job.directories = ["/foo", "/bar"] }

      it "overrides the UpateConfig's directories" do
        expect(source[:directories]).to eq(["/foo", "/bar"])
        expect(source[:directory]).to be_nil
      end
    end
  end

  describe "#credentials_metadata" do
    subject(:credentials_metadata) do
      serialized_update_job.credentials_metadata
    end

    context "when there are no credentials" do
      it "includes github credentials" do
        expect(credentials_metadata).
          to include({ "type" => "git_source", "host" => "github.com" })
      end

      it "includes tenant-scoped credentials in Proxima", :proxima do
        expect(credentials_metadata).
          to include({ "type" => "git_source", "host" => "staffship-01.ghe.com" })
      end
    end

    context "when there is an irrelevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(
          :registry, :docker,
          source: update_config.repo,
        )
      end
      let(:update_config) { update_job.update_config }

      before { update_config.package_manager = "bundler" }

      it "just includes github credentials", :cloud, :enterprise do
        expect(credentials_metadata).
          to eq([{ "type" => "git_source", "host" => "github.com" }])
      end

      it "includes tenant-scoped credentials in Proxima", :proxima do
        expect(credentials_metadata).
          to match_array([
                           { "type" => "git_source", "host" => "github.com" },
                           { "type" => "git_source", "host" => "staffship-01.ghe.com" },
                         ])
      end
    end

    context "when there is a relevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(
          :registry, :bundler,
          source: update_config.repo,
        )
      end
      let(:update_config) { update_job.update_config }

      before { update_config.package_manager = "bundler" }

      it "includes the registry (but not its credentials)", :cloud, :enterprise do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
              },
            ],
          )
      end

      it "includes tenant-scoped credentials in Proxima", :proxima do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
              {
                "type" => "git_source",
                "host" => "staffship-01.ghe.com",
              },
              {
                "type" => "rubygems_server",
                "host" => "gem.fury.io",
              },
            ],
          )
      end
    end

    context "when there is a public nuget registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(:registry,
                          registry_type: "nuget_feed",
                          source: update_config.repo,
                          credentials: { "url" => "https://api.nuget.org/v3/index.json" }.to_json)
      end
      let(:update_config) { update_job.update_config }

      before { update_config.package_manager = "nuget" }

      it "includes the registry (but not its credentials)", :cloud, :enterprise do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
              {
                "type" => "nuget_feed",
                "url" => "https://api.nuget.org/v3/index.json",
              },
            ],
          )
      end

      it "includes tenant-scoped credentials in Proxima", :proxima do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
              {
                "type" => "nuget_feed",
                "url" => "https://api.nuget.org/v3/index.json",
              },
              {
                "type" => "git_source",
                "host" => "staffship-01.ghe.com",
              },
            ],
          )
      end
    end

    context "when there is an unselected relevant registry" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let!(:registry) do
        FactoryBot.create(
          :registry, :bundler,
          source: update_config.repo,
        )
      end
      let(:update_config) { update_job.update_config }

      before do
        update_config.update(package_manager: "bundler", all_registries: false)
      end

      it "includes the registry (but not its credentials)", :cloud, :enterprise do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
            ],
          )
      end

      it "includes tenant-scoped credentials in Proxima", :proxima do
        expect(credentials_metadata).
          to match_array(
            [
              {
                "type" => "git_source",
                "host" => "github.com",
              },
              {
                "type" => "git_source",
                "host" => "staffship-01.ghe.com",
              },
            ],
          )
      end
    end
  end

  describe "#cooldown" do
    subject(:cooldown) { serialized_update_job.cooldown }

    context "when cooldown settings are present" do
      before do
        FactoryBot.create(
          :update_config_cooldown,
          update_config: update_job.update_config,
          default_days: 7,
          semver_major_days: 14,
          semver_minor_days: 7,
          semver_patch_days: 3,
          include: ["security"],
          exclude: ["low-priority"]
        )
      end

      it "returns the correct cooldown settings" do
        expect(cooldown).to eq(
          {
            "default-days" => 7,
            "semver-major-days" => 14,
            "semver-minor-days" => 7,
            "semver-patch-days" => 3,
            "include" => ["security"],
            "exclude" => ["low-priority"],
          }
        )
      end
    end

    context "when cooldown settings are not present" do
      it "returns nil" do
        expect(cooldown).to be_nil
      end
    end
  end

  describe "#debug" do
    subject(:credentials_metadata) do
      serialized_update_job.debug
    end

    it "is falsey by default" do
      expect(subject).to be_falsey
    end

    it "is true when the debug_logging feature flag is enabled" do
      update_job.repo.enable_feature(:debug_logging) # rubocop:disable Dependabot/NoLocalFeatureFlags

      expect(subject).to be true
    end
  end

  describe "#existing_pull_requests" do
    subject(:existing_pull_requests) do
      serialized_update_job.existing_pull_requests
    end

    it { is_expected.to eq([]) }

    context "when there is an existing pull request" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config)
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
        )
      end

      it "includes details of the PR" do
        expect(existing_pull_requests).
          to eq(
            [
              {
                pr_number: existing_pull_request.github_number,
                dependencies: [
                  {
                    dependency_name: "business",
                    dependency_version: "1.8.0",
                    directory: "/",
                  },
                ],
              },
            ]
          )
      end

      context "with change_pr_data_format feature flag" do
        context "when enabled" do
          it "returns new format with pr_number at top level" do
            expect(existing_pull_requests).
              to eq(
                [
                  {
                    pr_number: existing_pull_request.github_number,
                    dependencies: [
                      {
                        dependency_name: "business",
                        dependency_version: "1.8.0",
                        directory: "/",
                      },
                    ],
                  },
                ]
              )
          end
        end
      end

      context "that is merged" do
        before { existing_pull_request.transition_to!(:merged) }

        it { is_expected.to eq([]) }
      end

      context "that is pending" do
        before { existing_pull_request.transition_to!(:pending) }

        it { is_expected.to eq([]) }
      end

      context "that was marked closed after being merged" do
        before do
          existing_pull_request.transition_to!(:merged)
          existing_pull_request.transition_to!(:closed)
        end

        it { is_expected.to eq([]) }
      end

      context "that was marked as merged but reverted to open when the merge failed" do
        before do
          existing_pull_request.transition_to!(:merged)
          existing_pull_request.transition_to!(:up_to_date)
        end

        it "includes details of the PR" do
          expect(existing_pull_requests).
            to eq(
              [{
                pr_number: existing_pull_request.github_number,
                dependencies: [{ dependency_name: "business",
                                 dependency_version: "1.8.0",
                                 directory: "/", }],
              }],
            )
        end
      end

      context "that has a removed transitive dependency" do
        let!(:second_pull_request) do
          FactoryBot.create(
            :pull_request,
            update_job: previous_update_job,
            update_config: previous_update_job.update_config,
            dependencies: [
              {
                name: "removed",
                removed: true,
                previous_version: "1.1.1",
              },
              {
                name: "parent",
                version: "3.0.0",
                previous_version: "2.1.0",
              },
            ],
          )
        end

        it "includes details of the removed dependency PR" do
          expect(existing_pull_requests.count).to eq(2)
          expect(existing_pull_requests.first).
            to eq({
                    pr_number: existing_pull_request.github_number,
                    dependencies: [
                      {
                        dependency_name: "business",
                        dependency_version: "1.8.0",
                        directory: "/",
                      },
                    ],
                  })
          expect(existing_pull_requests.last).
            to eq({
                    pr_number: second_pull_request.github_number,
                    dependencies: [
                      {
                        dependency_name: "parent",
                        dependency_version: "3.0.0",
                        directory: "/",
                      },
                      {
                        dependency_name: "removed",
                        dependency_removed: true,
                        directory: "/",
                      },
                    ],
                  })
        end
      end
    end

    context "when there is an existing grouped update pull request" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config)
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
          grouped_update: true
        )
      end

      it "excludes the grouped update PR" do
        expect(existing_pull_requests).to be_empty
      end
    end
  end

  describe "#existing_group_pull_requests" do
    subject(:existing_group_pull_requests) do
      serialized_update_job.existing_group_pull_requests
    end

    it { is_expected.to eq([]) }

    context "when there is an existing grouped update pull request" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config)
      end
      let(:dependency_group) do
        FactoryBot.create(:dependency_group, name: "my-group", update_config: update_job.update_config)
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      it "includes details of the PR's group and dependencies" do
        expect(existing_group_pull_requests).
          to eq(
            [
              {
                dependency_group_name: "my-group",
                dependencies: [
                  { dependency_name: "business", dependency_version: "1.8.0", directory: "/" },
                ],
                pr_number: existing_pull_request.github_number,
              },
            ]
          )
      end

      it "includes the dependency's directory if it is set" do
        directory_name = "/my/directory"
        existing_pull_request.updated_dependencies.update_all(directory: directory_name)

        expect(existing_group_pull_requests).
          to eq(
            [
              {
                dependency_group_name: "my-group",
                dependencies: [
                  { dependency_name: "business",
                    dependency_version: "1.8.0",
                    directory: directory_name, },
                ],
                pr_number: existing_pull_request.github_number,
              },
            ]
          )
      end

      context "that is pending" do
        before { existing_pull_request.transition_to!(:pending) }

        it { is_expected.to eq([]) }
      end

      context "but it has been merged" do
        before { existing_pull_request.transition_to!(:merged) }

        it { is_expected.to eq([]) }
      end

      context "but it has been closed" do
        before { existing_pull_request.transition_to!(:closed) }

        it { is_expected.to eq([]) }
      end

      context "but the dependency group has been deleted" do
        before { dependency_group.delete }

        it { is_expected.to eq([]) }
      end
    end

    context "when there is an existing grouped update pull request without an associated group" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config)
      end
      let(:dependency_group) do
        FactoryBot.create(:dependency_group, name: "my-group")
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
          grouped_update: true,
        )
      end

      it "omits the pull request" do
        expect(existing_group_pull_requests).to eq([])
      end
    end

    context "when there's an existing grouped update PR without a group but it's a security update" do
      let(:update_job) { FactoryBot.create(:update_job, security_updates_only: true) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config, security_updates_only: true)
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
          grouped_update: true,
        )
      end

      it "includes the fallback group" do
        expect(existing_group_pull_requests).
          to eq(
            [
              {
                dependency_group_name: "bundler",
                dependencies: [{
                  dependency_name: "business",
                  dependency_version: "1.8.0",
                  directory: "/",
                }],
                pr_number: existing_pull_request.github_number,
              },
            ]
          )
      end
    end

    context "when there is an existing ungrouped pull request" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:previous_update_job) do
        FactoryBot.create(:update_job, update_config: update_job.update_config)
      end
      let!(:existing_pull_request) do
        FactoryBot.create(
          :pull_request,
          update_job: previous_update_job,
          update_config: previous_update_job.update_config,
        )
      end

      it { is_expected.to eq([]) }
    end
  end

  describe "#security_advisories" do
    subject(:security_advisories) do
      serialized_update_job.security_advisories
    end

    let(:package_manager) { "bundler" }

    let(:update_config) do
      FactoryBot.create(:update_config, package_manager: package_manager)
    end

    let(:update_job) do
      FactoryBot.create(:update_job,
                        update_config: update_config,
                        security_updates_only: true,
                        dependencies: ["abc"],
                        trigger_type: "push")
    end

    before do
      allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
    end

    it { is_expected.to eq([]) }

    context "when there is a GitHub Security Advisory" do
      let(:patched_versions) do
        ["> 2.5.14, <= 3.1.12", "> 3.1.13"]
      end

      let(:affected_versions) do
        ["< 2.5.14", "> 2.5.0, <= 2.5.14", "= 3.1.12-beta.rc5"]
      end

      before do
        mock_github_security_advisory_fetch(dependency_name: "abc",
                                            package_manager:,
                                            patched_versions: patched_versions,
                                            affected_versions: affected_versions)
      end

      it "includes details of the advisory" do
        expect(security_advisories).
          to eq(
            [
              {
                dependency_name: "abc",
                patched_versions: [],
                unaffected_versions: [],
                affected_versions: affected_versions,
              },
            ],
          )
      end
    end

    context "when there is a GitHub Security Advisory for NPM using bundler-like version notations" do
      let(:package_manager) { "npm_and_yarn" }

      let(:patched_versions) do
        ["> 2.5.14, <= 3.1.12", "> 3.1.13"]
      end

      let(:affected_versions) do
        ["< 2.5.14", "> 2.5.0, <= 2.5.14", "= 3.1.12-beta.rc5"]
      end

      before do
        mock_github_security_advisory_fetch(dependency_name: "abc",
                                            package_manager:,
                                            patched_versions:,
                                            affected_versions:)
      end

      it "corrects the affected versions" do
        expect(security_advisories).
          to eq(
            [
              {
                dependency_name: "abc",
                patched_versions: [],
                unaffected_versions: [],
                affected_versions: ["< 2.5.14", "> 2.5.0 <= 2.5.14", "= 3.1.12-beta.rc5"],
              },
            ],
          )
      end
    end

    context "when there is a GitHub Security Advisory for Maven using bundler-like version notations" do
      let(:package_manager) { "maven" }

      let(:patched_versions) do
        ["> 2.5.14, <= 3.1.12", "> 3.1.13"]
      end

      let(:affected_versions) do
        ["< 2.5.14", "> 2.5.0, <= 2.5.14", "= 3.1.12-beta.rc5"]
      end

      before do
        mock_github_security_advisory_fetch(dependency_name: "abc",
                                            package_manager: "maven",
                                            patched_versions:,
                                            affected_versions:)
      end

      it "corrects the version notations" do
        expect(security_advisories).
          to eq(
            [
              {
                dependency_name: "abc",
                patched_versions: [],
                unaffected_versions: [],
                affected_versions: ["(,2.5.14)", "(2.5.0,2.5.14]", "3.1.12-beta.rc5"],
              },
            ],
          )
      end
    end
  end

  describe "#ignore_conditions" do
    subject(:ignore_conditions) { serialized_update_job.ignore_conditions }

    it { is_expected.to eq([]) }

    context "when there is an ignore condition" do
      let(:update_job) { FactoryBot.create(:update_job) }
      let(:update_config) { update_job.update_config }
      let(:timestamp) do
        Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
      end
      let!(:ignore_condition) do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_config,
          updated_at: timestamp
        )
      end

      it "includes details of the ignore condition" do
        expect(ignore_conditions).
          to eq(
            [
              {
                dependency_name: "business",
                version_requirement: ">= 2.0, < 3",
                update_types: nil,
                source: "@dependabot ignore command",
                updated_at: timestamp,
              },
            ],
          )
      end

      context "for a different update config" do
        let!(:ignore_condition) { FactoryBot.create(:ignore_condition) }

        it { is_expected.to eq([]) }
      end

      context "with a requirement from config file" do
        let(:timestamp) do
          Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
        end
        let!(:ignore_condition) do
          FactoryBot.create(
            :ignore_condition,
            update_config: update_config,
            from_config_file: true,
            updated_at: timestamp
          )
        end

        it "includes details of the ignore condition" do
          expect(ignore_conditions).
            to eq(
              [{
                dependency_name: "business",
                version_requirement: ">= 2.0, < 3",
                update_types: nil,
                source: ".github/dependabot.yml",
                updated_at: timestamp,
              }],
            )
        end
      end

      context "with update types" do
        let(:timestamp) do
          Time.parse("2020-04-01 00:00 +0000").utc.iso8601(3)
        end
        let!(:ignore_condition) do
          FactoryBot.create(
            :ignore_condition,
            :ignore_patch,
            update_config: update_config,
            updated_at: timestamp
          )
        end

        it "includes details of the ignore condition" do
          expect(ignore_conditions).
            to eq(
              [{
                dependency_name: "business",
                version_requirement: nil,
                update_types: ["version-update:semver-patch"],
                source: "@dependabot ignore command",
                updated_at: timestamp,
              }],
            )
        end
      end
    end
  end

  describe "#dependency_groups" do
    it "returns an empty collection when there are no version-update dependency groups" do
      update_job = FactoryBot.create(:update_job, :version_update)
      serializer = described_class.new(update_job)

      expect(serializer.dependency_groups).to eq([])
    end

    it "serializes dependency groups" do
      update_job = FactoryBot.create(:update_job)
      FactoryBot.create(
        :dependency_group,
        update_config: update_job.update_config,
        name: "rails",
        rules: { "patterns": ["active*"], "exclude-patterns": ["activerecord"] }
      )
      serializer = described_class.new(update_job)

      expect(serializer.dependency_groups).
        to eq([
                {
                  "name" => "rails",
                  "rules" => {
                    "patterns" => [
                      "active*",
                    ],
                    "exclude-patterns" => [
                      "activerecord",
                    ],
                  },
                },
              ])
    end

    it "serializes dependency groups with group-by" do
      update_job = FactoryBot.create(:update_job)
      FactoryBot.create(
        :dependency_group,
        update_config: update_job.update_config,
        name: "per-dependency",
        rules: { "group-by" => "dependency-name" }
      )
      serializer = described_class.new(update_job)

      expect(serializer.dependency_groups).
        to eq([
                {
                  "name" => "per-dependency",
                  "rules" => { "group-by" => "dependency-name" },
                },
              ])
    end

    it "serializes dependency groups with group-by alongside other rules" do
      update_job = FactoryBot.create(:update_job)
      FactoryBot.create(
        :dependency_group,
        update_config: update_job.update_config,
        name: "dev-per-dependency",
        rules: { "patterns" => ["dev-*"], "group-by" => "dependency-name" }
      )
      serializer = described_class.new(update_job)

      expect(serializer.dependency_groups).
        to eq([
                {
                  "name" => "dev-per-dependency",
                  "rules" => {
                    "patterns" => ["dev-*"],
                    "group-by" => "dependency-name",
                  },
                },
              ])
    end

    context "with the group order ff enabled" do
      it "does not include the sort order" do
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "rails",
          rules: { "patterns": ["test*"] },
          sort_order: 5
        )
        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).
          to eq([
                  {
                    "name" => "rails",
                    "rules" => {
                      "patterns" => [
                        "test*",
                      ],
                    },
                  },
                ])
      end

      it "sorts the groups by the sort order" do
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "rails",
          rules: { "patterns": ["test*"] },
          sort_order: 5
        )
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "ruby",
          rules: { "patterns": ["ruby*"] },
          sort_order: 1
        )
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "graphql",
          rules: { "patterns": ["graphql*"] },
          sort_order: 2
        )
        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).
          to eq([
                  {
                    "name" => "ruby",
                    "rules" => {
                      "patterns" => [
                        "ruby*",
                      ],
                    },
                  },
                  {
                    "name" => "graphql",
                    "rules" => {
                      "patterns" => [
                        "graphql*",
                      ],
                    },
                  },
                  {
                    "name" => "rails",
                    "rules" => {
                      "patterns" => [
                        "test*",
                      ],
                    },
                  },
                ])
      end
    end

    it "excludes logically deleted dependency groups" do
      update_job = FactoryBot.create(:update_job)
      FactoryBot.create(
        :dependency_group,
        :deleted,
        update_config: update_job.update_config,
        name: "rails",
        rules: { "patterns": ["active*"] }
      )
      serializer = described_class.new(update_job)

      expect(serializer.dependency_groups).to eq([])
    end

    context "with an update-types rule specified" do
      it "serializes any persisted advanced rules" do
        update_job = FactoryBot.create(:update_job)

        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "rails",
          rules: {
            "patterns": ["active*"],
            "dependency-type": "production",
            "update-types": ["minor"],
          }
        )

        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).
          to eq([
                  {
                    "name" => "rails",
                    "rules" => {
                      "patterns" => [
                        "active*",
                      ],
                      "dependency-type" => "production",
                      "update-types" => ["minor"],
                    },
                  },
                ])
      end
    end

    context "with an applies-to specified" do
      it "serializes applies-to" do
        update_job = FactoryBot.create(:update_job, :security_update)

        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "rails",
          applies_to: "security-updates",
          rules: {
            "patterns": ["active*"],
          }
        )

        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).
          to eq([
                  {
                    "name" => "rails",
                    "applies-to" => "security-updates",
                    "rules" => {
                      "patterns" => [
                        "active*",
                      ],
                    },
                  },
                ])
      end
    end

    context "when a grouped security update has no user-defined dependency groups" do
      it "serializes a fallback group" do
        stub_monolith_settings(security_updates_grouping_enabled: true)

        dependencies = %w(business)
        update_job = FactoryBot.create(:update_job, :security_update, dependencies: dependencies)

        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).
          to eq([
                  {
                    "name" => update_job.package_manager,
                    "applies-to" => "security-updates",
                    "rules" => {
                      "patterns" => ["*"],
                    },
                  },
                ])
      end
    end

    context "when a grouped security update has user-defined version update groups but no security groups" do
      it "does not serialize a fallback group to avoid phantom groups" do
        stub_monolith_settings(security_updates_grouping_enabled: true)

        dependencies = %w(business)
        update_job = FactoryBot.create(:update_job, :security_update, dependencies: dependencies)

        # Create a version update group (applies_to defaults to "version-updates")
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "js-minor",
          rules: {
            "patterns": ["*"],
            "update-types": %w(minor patch),
          }
        )

        serializer = described_class.new(update_job)

        expect(serializer.dependency_groups).to eq([])
      end
    end
  end

  describe "#allowed_updates" do
    subject(:allowed_updates) { serialized_update_job.allowed_updates }

    it "serialises the default allowed_updates" do
      expect(subject).to eq(
        [
          {
            "dependency_type" => "direct",
            "update_type" => "all",
          },
        ]
      )
    end

    context "when security updates only job" do
      let(:update_job) { FactoryBot.create(:update_job, :security) }

      it "only allows security updates" do
        expect(subject).to eq(
          [
            {
              "dependency_type" => "direct",
              "update_type" => "all",
            },
          ]
        )
      end
    end

    context "when allowed_updates includes update_types" do
      before do
        update_job.update_config.update!(
          allowed_updates: [
            {
              "dependency_name" => "rails",
              "update_types" => %w(version-update:semver-minor version-update:semver-patch),
            },
          ]
        )
      end

      it "serialises update_types in allowed_updates" do
        expect(subject).to eq(
          [
            {
              "dependency_name" => "rails",
              "update_types" => %w(version-update:semver-minor version-update:semver-patch),
            },
          ]
        )
      end
    end
  end

  describe "#security_updates_only" do
    subject(:security_updates_only) { serialized_update_job.security_updates_only }

    it { is_expected.to eq(false) }

    context "when security updates only job" do
      let(:update_job) { FactoryBot.create(:update_job, :security) }

      it { is_expected.to eq(true) }
    end
  end

  describe "#experiments" do
    subject(:experiments) { serialized_update_job.as_json[:experiments] }

    context "when the `timeout_per_operation` feature is enabled" do
      before { update_job.repo.enable_feature(:timeout_per_operation) } # rubocop:disable Dependabot/NoLocalFeatureFlags

      specify { expect(experiments).to include(timeout_per_operation_seconds: 600) }
    end
  end

  describe "#updating_a_pull_request" do
    subject(:updating_a_pull_request) { serialized_update_job.as_json[:updating_a_pull_request] }

    context "when not updating a pull request" do
      specify { expect(updating_a_pull_request).to eq(false) }
    end

    context "when updating a pull request" do
      let(:pull_request) do
        FactoryBot.create(:pull_request)
      end

      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first
      end

      specify { expect(updating_a_pull_request).to eq(true) }
    end

    context "when trigger_type is rebase but pull_request_transition_id is nil" do
      let(:update_job) { FactoryBot.create(:update_job, trigger_type: "rebase", pull_request_transition_id: nil) }

      specify { expect(updating_a_pull_request).to eq(true) }
    end

    context "when trigger_type is manual_rebase but pull_request_transition_id is nil" do
      let(:update_job) do
        FactoryBot.create(:update_job, trigger_type: "manual_rebase", pull_request_transition_id: nil)
      end

      specify { expect(updating_a_pull_request).to eq(true) }
    end
  end

  describe "#multi_ecosystem_update" do
    subject(:multi_ecosystem_update) { serialized_update_job.as_json[:multi_ecosystem_update] }

    context "when not a multi-ecosystem update" do
      specify { expect(multi_ecosystem_update).to eq(false) }
    end

    context "when a multi-ecosystem update" do
      let(:pull_request) { create(:pull_request, :for_a_multi_ecosystem_update) }

      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first
      end

      specify { expect(multi_ecosystem_update).to eq(true) }
    end
  end

  describe "#dependency_group_to_refresh" do
    subject(:dependency_group_to_refresh) { serialized_update_job.as_json[:dependency_group_to_refresh] }

    context "when not updating a pull request" do
      it { is_expected.to be_nil }
    end

    context "when updating a non-grouped pull request" do
      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          grouped_update: false,
          dependency_group: nil
        )
      end

      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first
      end

      it { is_expected.to be_nil }
    end

    context "when updating a grouped pull request" do
      let(:dependency_group) do
        FactoryBot.create(
          :dependency_group,
          name: "my-group",
          rules: {
            patterns: [
              "foo-*",
            ],
          }
        )
      end

      let(:pull_request) do
        FactoryBot.create(
          :pull_request,
          grouped_update: true,
          dependency_group: dependency_group
        )
      end

      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first
      end

      it "is expected to serialize the DependencyGroup" do
        expect(dependency_group_to_refresh).to eql("my-group")
      end
    end

    context "when updating a multi-ecosystem grouped pull request" do
      let(:pull_request) { create(:pull_request, :for_a_multi_ecosystem_update) }

      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first
      end

      it "is expected to serialize the DependencyGroup" do
        expect(dependency_group_to_refresh).to eql("my_multi_ecosystem_config")
      end
    end

    context "when updating a grouped security pull request for a config with version \n
             update groups but no security groups" do
      let(:pull_request) { FactoryBot.create(:pull_request, grouped_update: true) }
      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first.tap do |job|
          job.update(security_updates_only: true)
        end
      end

      before do
        # Create a version update group (applies_to defaults to "version-updates")
        FactoryBot.create(
          :dependency_group,
          update_config: update_job.update_config,
          name: "js-minor",
          rules: {
            "patterns": ["*"],
            "update-types": %w(minor patch),
          }
        )
      end

      it "does not serialize a fallback dependency group to avoid phantom groups" do
        allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
        stub_monolith_settings(security_updates_grouping_enabled: true)

        expect(dependency_group_to_refresh).to be_nil
      end

      it "does not report the use of the fallback dependency group" do
        allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
        stub_monolith_settings(security_updates_grouping_enabled: true)

        expect(MetricsClient).not_to receive(:count).with("fallback_dependency_group_used", 1, be_a(Hash))

        dependency_group_to_refresh
      end
    end

    context "when updating a grouped security pull request for a config with no defined groups" do
      let(:pull_request) { FactoryBot.create(:pull_request, grouped_update: true) }
      let(:update_job) do
        pull_request.transition_to!(:updating)
        pull_request.create_rebase_update_jobs.first.tap do |job|
          job.update(security_updates_only: true)
        end
      end

      it "serializes a (fallback) dependency group for the package manager" do
        allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
        stub_monolith_settings(security_updates_grouping_enabled: true)

        expect(dependency_group_to_refresh).to eq(update_job.package_manager)
      end

      it "reports the use of the fallback dependency group" do
        allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([])
        stub_monolith_settings(security_updates_grouping_enabled: true)

        expect(MetricsClient).
          to receive(:count).
          with("fallback_dependency_group_used", 1, be_a(Hash))

        dependency_group_to_refresh
      end
    end
  end

  describe "#repo_private" do
    subject(:repo_private) { serialized_update_job.as_json[:repo_private] }

    context "when the repo is private" do
      it { is_expected.to eq(true) }
    end

    context "when the repo is public" do
      before { update_job.repo.update!(private: false) }

      it { is_expected.to eq(false) }
    end
  end

  describe "#enable_beta_ecosystems" do
    subject(:enable_beta_ecosystems) do
      serialized_update_job.as_json[:enable_beta_ecosystems]
    end

    context "when the :enable_beta_ecosystems feature is not enabled" do
      it { is_expected.to eq(false) }
    end

    context "when the update_config has enable beta ecosystems set to true" do
      before do
        update_job.update_config.update!(enable_beta_ecosystems: true)
      end

      it { is_expected.to eq(true) }
    end
  end
end
