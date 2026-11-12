# frozen_string_literal: true

require "rails_helper"
require "ecosystem_file_regex"

RSpec.describe UpdateConfig, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  subject(:update_config) { FactoryBot.build(:update_config) }

  let(:redis) { Dependabot.redis }

  before do
    allow(MetricsClient).to receive(:increment)
  end

  after { redis.flushdb }

  it { is_expected.to be_valid }

  describe "validations" do
    describe "requirements_update_strategy" do
      context "with no strategy specified" do
        before { update_config.requirements_update_strategy = nil }

        it { is_expected.to be_valid }
      end

      context "with a strategy specified" do
        before { update_config.requirements_update_strategy = strategy }

        let(:strategy) { "widen_ranges" }

        context "for a package manager that doesn't support them" do
          before { update_config.package_manager = "bundler" }

          it { is_expected.not_to be_valid }
        end

        context "for a package manager that does support them" do
          before { update_config.package_manager = "npm_and_yarn" }

          it { is_expected.to be_valid }

          context "but this strategy is invalid" do
            let(:strategy) { "yolo" }

            it { is_expected.not_to be_valid }
          end
        end
      end

      context "with the lockfile_only strategy specified" do
        before { update_config.requirements_update_strategy = strategy }

        let(:strategy) { "lockfile_only" }

        context "for a package manager that doesn't support them" do
          before { update_config.package_manager = "gradle" }

          it { is_expected.not_to be_valid }
        end

        context "for a package manager that does support them" do
          before { update_config.package_manager = "npm_and_yarn" }

          it { is_expected.to be_valid }
        end
      end
    end

    describe "allowed_updates" do
      context "with no allowed_updates specified" do
        before { update_config.allowed_updates = nil }

        it { is_expected.not_to be_valid }
      end

      context "with allowed_updates" do
        before { update_config.allowed_updates = allowed_updates }

        context "for an 'all' update type" do
          let(:allowed_updates) { [{ "update_type" => "all" }] }

          it { is_expected.to be_valid }
        end

        context "for a 'security' update type" do
          let(:allowed_updates) { [{ "update_type" => "security" }] }

          it { is_expected.to be_valid }
        end

        context "for an unknown update type" do
          let(:allowed_updates) { [{ "update_type" => "unknown" }] }

          it { is_expected.not_to be_valid }
        end

        context "with a dependency whitelist" do
          let(:allowed_updates) { [{ "dependency_name" => "unknown" }] }

          it { is_expected.to be_valid }

          context "that doesn't specify a string" do
            let(:allowed_updates) { [{ "dependency_name" => nil }] }

            it { is_expected.not_to be_valid }
          end
        end

        context "without an array wrapper" do
          let(:allowed_updates) { { "update_type" => "all" } }

          it { is_expected.not_to be_valid }
        end

        context "with an unexpected object in the array" do
          let(:allowed_updates) { [{ "update_type" => "all" }, nil] }

          it { is_expected.not_to be_valid }
        end
      end
    end

    describe "commit_message_prefix" do
      context "with a valid prefix" do
        before { update_config.commit_message_prefix = "chore" }

        it { is_expected.to be_valid }
      end

      context "with a prefix that is too long" do
        before { update_config.commit_message_prefix = "a" * 51 }

        it { is_expected.not_to be_valid }
      end
    end

    describe "commit_message_prefix_development" do
      context "with a valid prefix" do
        before { update_config.commit_message_prefix_development = "chore" }

        it { is_expected.to be_valid }
      end

      context "with a prefix that is too long" do
        before { update_config.commit_message_prefix_development = "a" * 51 }

        it { is_expected.not_to be_valid }
      end
    end

    describe "validate_directories_uniqueness" do
      let(:repo) { FactoryBot.create(:repo, :active) }
      let(:repo_id) { repo.id }
      let(:package_manager) { "npm_and_yarn" }
      let(:target_branch) { "main" }

      before do
        update_config.repo_id = repo_id
        update_config.package_manager = package_manager
        update_config.target_branch = target_branch
      end

      context "when directories is not present" do
        before { update_config.directories = nil }

        it "is valid when directories is nil" do
          expect(update_config).to be_valid
        end
      end

      context "when directories is empty" do
        before { update_config.directories = [] }

        it "is valid when directories is empty" do
          expect(update_config).to be_valid
        end
      end

      context "when directories has unique values" do
        before do
          update_config.directory = nil
          update_config.directories = ["/unique/path"]
        end

        it "is valid when directories has unique values" do
          expect(update_config).to be_valid
        end
      end

      context "when directories has duplicate values within the same record" do
        before { update_config.directories = ["/duplicate/path", "/duplicate/path"] }

        it "is invalid when any directory is a duplicate within the same record" do
          expect(update_config).not_to be_valid
        end
      end

      context "when directories has unique values across different records" do
        before do
          described_class.create!(
            repo_id: repo_id,
            package_manager: package_manager,
            target_branch: target_branch,
            directory: nil,
            directories: ["/duplicate/path", "/unique/path"],
            update_schedule: "daily",
            update_schedule_day_of_week: "monday",
            update_schedule_time_of_day: "10:00",
            update_schedule_timezone: "Europe/London",
            lockfile_only: "true", # Assuming 'true' is a valid value
            allowed_updates: [{ "dependency_name" => "business" }],
            pull_request_branch_name_separator: "-",
            rebase_strategy: "auto",
            default_labels: ["default"],
            open_pull_requests_limit: 1,
          )
          update_config.directory = nil
          update_config.directories = ["/duplicate/path", "/unique/path"]
        end

        it "is valid when directories has unique values across records" do
          expect(update_config).to be_valid
        end
      end

      context "when directories has unique values across different records in cron expression context" do
        before do
          described_class.create!(
            repo_id: repo_id,
            package_manager: package_manager,
            target_branch: target_branch,
            directory: nil,
            directories: ["/duplicate/path", "/unique/path"],
            update_schedule: "cron",
            update_schedule_cron_expression: "0 5 * * *",
            update_schedule_timezone: "Europe/London",
            update_schedule_day_of_week: "monday",
            update_schedule_time_of_day: "10:00",
            lockfile_only: "true", # Assuming 'true' is a valid value
            allowed_updates: [{ "dependency_name" => "business" }],
            pull_request_branch_name_separator: "-",
            rebase_strategy: "auto",
            default_labels: ["default"],
            open_pull_requests_limit: 1,
          )
          update_config.directory = nil
          update_config.directories = ["/duplicate/path", "/unique/path"]
        end

        it "is valid when directories has unique values across records" do
          expect(update_config).to be_valid
        end
      end

      context "when directories has both unique and duplicate values across different records" do
        let(:existing_config) do
          described_class.create!(
            repo_id: repo_id,
            package_manager: package_manager,
            target_branch: target_branch,
            directory: nil,
            directories: ["/existing/path", "/unique/path"],
            update_schedule: "daily",
            update_schedule_day_of_week: "monday",
            update_schedule_time_of_day: "10:00",
            update_schedule_timezone: "Europe/London",
            lockfile_only: "true",
            allowed_updates: [{ "dependency_name" => "business" }],
            pull_request_branch_name_separator: "-",
            rebase_strategy: "auto",
            default_labels: ["default"],
            open_pull_requests_limit: 1,
          )
        end

        before do
          existing_config.transition_to!(:rate_limited)
          existing_config.transition_to!(:active)
          update_config.directory = nil
          update_config.directories = ["/new/path", "/unique/path"]
        end

        it "is valid when the combination of directories is unique across records" do
          expect(update_config).to be_valid
        end
      end
    end

    describe "validate_directory_xor_directories" do
      context "when both directory and directories are present" do
        before do
          update_config.directory = "/"
          update_config.directories = ["/path"]
        end

        it "is invalid" do
          expect(update_config).not_to be_valid
        end
      end
    end

    describe "validate_directories_are_sorted" do
      context "when directories are not sorted" do
        before do
          update_config.directory = nil
          update_config.directories = ["/b", "/a"]
        end

        it "is invalid" do
          expect(update_config).not_to be_valid
          expect(update_config.errors[:directories]).to include("must be sorted")
        end
      end

      context "when directories are sorted" do
        before do
          update_config.directory = nil
          update_config.directories = ["/a", "/b"]
        end

        it "is valid" do
          expect(update_config).to be_valid
        end
      end
    end
  end

  describe "callbacks" do
    describe "on validation" do
      describe "on create" do
        it "sets the required_instance_size" do
          expect { update_config.valid? }.
            to change(update_config, :required_instance_size).
            from(nil).to("t3.small")
        end

        context "when a required_instance_size has been set already" do
          before { update_config.required_instance_size = "t3.medium" }

          it "does not set the required_instance_size" do
            expect { update_config.valid? }.
              not_to change(update_config, :required_instance_size)
          end
        end
      end
    end

    describe "after updating the target_branch" do
      context "with a PR" do
        subject(:update_config) { pull_request.update_config }

        let!(:pull_request) { FactoryBot.create(:pull_request) }

        it "enqueues an UpdatePullRequestBaseBranchJob for the PR" do
          expect { update_config.update!(target_branch: "develop") }.
            to have_enqueued_job(UpdatePullRequestBaseBranchJob).
            with(pull_request: pull_request)
        end

        context "that is closed" do
          let!(:pull_request) { FactoryBot.create(:pull_request, :closed) }

          it "does not enqueue an UpdatePullRequestBaseBranchJob for the PR" do
            expect { update_config.update!(target_branch: "develop") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end

        context "after an unrelated change" do
          it "does not enqueue an UpdatePullRequestBaseBranchJob" do
            expect { update_config.update!(directory: "something-else") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end

        context "the repository is currently paused", feature: :inactivity_pausing do
          subject(:repo) { update_config.repo }

          let!(:pull_request) { FactoryBot.create(:pull_request) }

          before do
            repo.update!(paused_at: 1.minute.ago)
          end

          it "does not enqueue an UpdatePullRequestBaseBranchJob for the PR" do
            expect { update_config.update!(target_branch: "develop") }.
              not_to have_enqueued_job(UpdatePullRequestBaseBranchJob)
          end
        end
      end
    end

    describe "after create" do
      it "instruments create" do
        tags = {
          package_manager: "bundler",
          update_schedule: "daily",
        }
        expect(MetricsClient).to receive(:increment).
          with("update_config.created", tags: tags)
        update_config.save!
      end
    end
  end

  describe "#cooldown" do
    context "when update_config_cooldown is present" do
      let!(:update_config_cooldown) do
        FactoryBot.create(
          :update_config_cooldown,
          update_config: update_config,
          default_days: 7,
          semver_major_days: 14,
          semver_minor_days: 7,
          semver_patch_days: 1,
          include: ["dependency1"],
          exclude: ["dependency2"]
        )
      end

      it "returns the cooldown settings" do
        expect(update_config.cooldown).to eq(
          "default-days" => 7,
          "semver-major-days" => 14,
          "semver-minor-days" => 7,
          "semver-patch-days" => 1,
          "include" => ["dependency1"],
          "exclude" => ["dependency2"]
        )
      end
    end

    context "when update_config_cooldown is not present" do
      it "returns nil" do
        expect(update_config.cooldown).to be_nil
      end
    end
  end

  describe ".path_matches_updated_files_regex?" do
    def path_matches_updated_files_regex?(package_manager, path)
      regex_provider = EcosystemFileRegex.new(package_manager)
      updated_files_regex = regex_provider.updated_files_regex
      described_class.path_matches_updated_files_regex?(
        updated_files_regex,
        path,
      )
    end

    it "matches the filename against the package manager" do
      expect(path_matches_updated_files_regex?("bundler", "Gemfile")).to be_truthy
    end

    it "matches the filename when nested inside a folder" do
      expect(path_matches_updated_files_regex?("bundler", "dir/app/Gemfile")).to be_truthy
    end

    it "matches the path for github actions" do
      expect(path_matches_updated_files_regex?("github_actions", "test.yml")).to be_truthy
      expect(path_matches_updated_files_regex?("github_actions", ".github/workflows/test.yml")).
        to be_truthy
    end

    it "doesn't match the filename for github actions" do
      expect(path_matches_updated_files_regex?("github_actions", "test.sarif")).to be_falsy
    end

    it "doesn't match the filename for a different package manager" do
      expect(path_matches_updated_files_regex?("bundler", "package.json")).to be_falsy
    end
  end

  describe "#last_update_run" do
    subject(:last_update_run) { update_config.last_update_run }

    context "with no update runs" do
      it { is_expected.to be_nil }
    end

    context "with an update run" do
      let!(:update_job) do
        FactoryBot.create(:update_job, update_config: update_config)
      end

      it { is_expected.to eq(update_job) }

      context "that was followed by an update run" do
        let!(:pull_request) do
          # Creates two update jobs: one for the initial PR, and a second when
          # transitioned to "updating"
          FactoryBot.create(
            :pull_request, :updating,
            update_config: update_config,
          )
        end

        it "is the last update job that isn't updating a PR" do
          expect(last_update_run).to eq(pull_request.update_job)
          expect(last_update_run).not_to eq(UpdateJob.last)
        end
      end
    end
  end

  describe "#ignored_update?" do
    subject { update_config.ignored_update?(updated_dependency) }

    let!(:update_config) { FactoryBot.create(:update_config, package_manager: package_manager) }
    let(:updated_dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: dependency_version,
        previous_version: dependency_previous_version,
        requirements: [],
        package_manager: package_manager,
      )
    end
    let(:dependency_name) { "business" }
    let(:package_manager) { "bundler" }
    let(:dependency_version) { "1.5.0" }
    let(:dependency_previous_version) { "1.4.0" }

    context "with no ignore conditions" do
      it { is_expected.to eq(false) }
    end

    context "with an ignored version that doesn't match" do
      before do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_config,
          dependency_name: "business",
          version_requirement: "~> 2.0",
        )
      end

      it { is_expected.to eq(false) }
    end

    context "with an ignored version that does match" do
      before do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_config,
          dependency_name: ignored_dependency_name,
          version_requirement: "~> 1.0",
        )
      end

      let(:ignored_dependency_name) { "business" }

      it { is_expected.to eq(true) }

      context "for a different dependency" do
        let(:ignored_dependency_name) { "bus" }

        it { is_expected.to eq(false) }
      end

      context "for a wildcard match" do
        let(:ignored_dependency_name) { "bus*" }

        it { is_expected.to eq(true) }
      end

      context "for a normalised match" do
        let(:package_manager) { "pip" }
        let(:ignored_dependency_name) { "Bus_iness" }
        let(:dependency_name) { "bus.iness" }

        it { is_expected.to eq(true) }
      end
    end

    context "for a non-numeric version" do
      let(:dependency_version) { "a1a2a4" }

      it { is_expected.to eq(false) }

      context "with an ignore condition for non-numeric versions" do
        before do
          FactoryBot.create(
            :ignore_condition,
            update_config: update_config,
            dependency_name: "business",
            version_requirement: ">= 0",
          )
        end

        it { is_expected.to eq(true) }
      end
    end

    context "when ignoring patch releases" do
      let(:dependency_version) { "1.0.1" }
      let(:dependency_previous_version) { "1.0.0" }

      before do
        FactoryBot.create(
          :ignore_condition,
          :ignore_patch,
          update_config: update_config,
        )
      end

      it { is_expected.to eq(true) }

      context "when the update is minor" do
        let(:dependency_version) { "1.1.0" }
        let(:dependency_previous_version) { "1.0.0" }

        it { is_expected.to eq(false) }
      end
    end

    context "when ignoring major releases" do
      let(:dependency_version) { "2.0.0" }
      let(:dependency_previous_version) { "1.0.0" }

      before do
        FactoryBot.create(
          :ignore_condition,
          :ignore_major,
          update_config: update_config,
        )
      end

      it { is_expected.to eq(true) }

      context "when the update is minor" do
        let(:dependency_version) { "1.1.0" }
        let(:dependency_previous_version) { "1.0.0" }

        it { is_expected.to eq(false) }
      end
    end

    context "with a removed transitive dependency" do
      let(:updated_dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          previous_version: dependency_previous_version,
          requirements: [],
          package_manager: package_manager,
          removed: true
        )
      end

      before do
        FactoryBot.create(
          :ignore_condition,
          update_config: update_config,
          dependency_name: "business",
          version_requirement: "~> 2.0",
        )
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "#update_subdependencies?" do
    subject { update_config.update_subdependencies? }

    context "when security updates are allowed for all dependency types" do
      before do
        update_config.allowed_updates = [{ "update_type" => "security" }]
      end

      it { is_expected.to eq(false) }
    end

    context "when all updates are allowed for all dependency types" do
      before do
        update_config.allowed_updates = [{ "update_type" => "all" }]
      end

      it { is_expected.to eq(true) }
    end

    context "when all updates are allowed for indirect dependencies" do
      before do
        update_config.allowed_updates = [
          { "update_type" => "all", "dependency_type" => "indirect" },
        ]
      end

      it { is_expected.to eq(true) }
    end

    context "when security updates are allowed for indirect dependencies" do
      before do
        update_config.allowed_updates = [
          { "update_type" => "security", "dependency_type" => "indirect" },
        ]
      end

      it { is_expected.to eq(false) }
    end

    context "when all updates are allowed for a whitelisted dependency" do
      before do
        update_config.allowed_updates = [{ "dependency_name" => "rails" }]
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "#recently_triggered_scheduled_update_job?" do
    subject { update_config.recently_triggered_scheduled_update_job? }

    before do
      update_config.save
    end

    context "when an update job was triggered recently" do
      before { update_config.update_jobs.create!(trigger_type: :schedule) }

      it { is_expected.to eq(true) }
    end

    context "when an ASU job was triggered recently" do
      before { update_config.update_jobs.create!(trigger_type: :manual) }

      it { is_expected.to eq(false) }
    end

    context "when an update job was triggered a while ago" do
      before do
        travel_to(5.minutes.ago) do
          update_config.update_jobs.create!(trigger_type: :schedule)
        end
      end

      it { is_expected.to eq(false) }
    end
  end

  describe "#transition_to!" do
    context "when invalid" do
      let(:repo) do
        FactoryBot.create(:repo)
      end
      let!(:first_duplicate_update_config) do
        FactoryBot.create(:update_config, repo: repo)
      end
      let!(:second_duplicate_update_config) do
        FactoryBot.create(:update_config, repo: repo)
      end

      it "cannot transition" do
        first_duplicate_update_config.transition_to!(:rate_limited)

        expect { second_duplicate_update_config.transition_to!(:rate_limited) }.
          to raise_error(Statesman::GuardFailedError)
      end
    end
  end

  describe "#update_schedule_time_of_day" do
    subject(:update_schedule_time_of_day) do
      update_config.reload.update_schedule_time_of_day
    end

    let(:time_of_day) { "04:20" }
    let(:parsed_time_of_day) do
      # Rails defaults to 2000-01-01 when no date is set:
      # https://github.com/rails/rails/blob/master/activemodel/lib/active_model/type/time.rb
      Time.zone.parse("2000-01-01 #{time_of_day}")
    end
    let!(:update_config) do
      FactoryBot.create(:update_config,
                        update_schedule_time_of_day: time_of_day)
    end

    it { is_expected.to eq(parsed_time_of_day) }

    # Handle a bug that seems to originate in MySQL date handling where 00-00 is
    # treated as a dummy date and converted to nil:
    # https://dev.mysql.com/doc/refman/5.7/en/date-and-time-types.html
    context "when set to midnight" do
      let(:time_of_day) { "00:00" }

      it { is_expected.to eq(parsed_time_of_day) }
    end
  end

  describe "#supports_lockfile?" do
    subject { update_config.supports_lockfile? }

    let(:update_config) { FactoryBot.build(:update_config) }

    package_managers_without_lockfiles =
      PackageManagers::ALL -
      described_class::PACKAGE_MANAGERS_WITH_LOCKFILES.keys

    package_managers_without_lockfiles.each do |pm|
      it "#{pm} doesn't support lockfiles" do
        update_config.package_manager = pm
        expect(subject).to be_falsy
      end
    end

    described_class::PACKAGE_MANAGERS_WITH_LOCKFILES.each_key do |pm|
      it "#{pm} supports lockfiles" do
        update_config.package_manager = pm
        expect(subject).to be_truthy
      end
    end
  end

  package_managers_without_code_execution =
    PackageManagers::ALL -
    described_class::PACKAGE_MANAGERS_WITH_CODE_EXECUTION

  describe "#supports_repository_access?" do
    subject { update_config.supports_repository_access? }

    let(:repo) { FactoryBot.create(:repo, private: true) }
    let(:update_config) { FactoryBot.build(:update_config, repo: repo) }

    package_managers_without_code_execution.each do |pm|
      it "#{pm} supports repository access" do
        update_config.package_manager = pm
        expect(subject).to be_truthy
      end
    end

    context "for a public repo" do
      subject { update_config.supports_repository_access? }

      let(:repo) do
        FactoryBot.create(:repo, private: false)
      end

      let(:update_config) { FactoryBot.create(:update_config, repo: repo) }

      it "does not support repository access" do
        expect(subject).to be_falsy
      end
    end

    described_class::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.each do |pm|
      it "#{pm} does not support repository access" do
        update_config.package_manager = pm
        expect(subject).to be_falsy
      end
    end
  end

  describe "#reject_external_code?" do
    subject { update_config.reject_external_code? }

    let(:update_config) { FactoryBot.build(:update_config) }

    context "no registries" do
      PackageManagers::ALL.each do |pm|
        it "#{pm} does not reject external code" do
          update_config.package_manager = pm
          expect(subject).to eq(false)
        end
      end
    end

    context "with registry" do
      before do
        update_config.update(all_registries: true)
        FactoryBot.create(:registry, :git, source: update_config.repo)
      end

      described_class::PACKAGE_MANAGERS_WITH_CODE_EXECUTION.each do |pm|
        it "#{pm} rejects external code if config implicitly denies it" do
          update_config.package_manager = pm
          update_config.insecure_external_code_execution = nil
          expect(subject).to eq(true)
        end

        it "#{pm} rejects external code if config explicitly denies it" do
          update_config.package_manager = pm
          update_config.insecure_external_code_execution = "deny"
          expect(subject).to eq(true)
        end

        it "#{pm} does not reject external code execution if config explicitly allows it" do
          update_config.package_manager = pm
          update_config.insecure_external_code_execution = "allow"
          expect(subject).to eq(false)
        end
      end

      package_managers_without_code_execution.each do |pm|
        it "#{pm} does not reject external code" do
          update_config.package_manager = pm
          expect(subject).to eq(false)
        end
      end
    end
  end

  describe "#formatted_lockfile_name" do
    subject { update_config.formatted_lockfile_name }

    let(:update_config) { FactoryBot.build(:update_config) }

    it "returns the supported lockfile, when just a single lockfile supported" do
      update_config.package_manager = "pub"
      expect(subject).to eq("pubspec.lock")
    end

    it "returns the supported lockfiles joined by 'or', when two lockfiles supported" do
      update_config.package_manager = "bundler"
      expect(subject).to eq("Gemfile.lock or gems.locked")
    end

    it "returns the supported lockfiles joined by ',' and trailing 'or', when more than two lockfiles supported" do
      update_config.package_manager = "pip"
      expect(subject).to eq("Pipfile.lock, pyproject.lock or poetry.lock")
    end

    described_class::PACKAGE_MANAGERS_WITH_LOCKFILES.each_key do |pm|
      it "#{pm} has a formatted lockfile name" do
        update_config.package_manager = pm
        expect(subject).not_to be_empty
      end
    end

    context "for a package manager that doesn't support lockfiles" do
      before do
        update_config.package_manager = "maven"
      end

      it "returns nil" do
        expect(subject).to be_nil
      end
    end
  end

  describe "#registries" do
    subject(:registries) { update_config.registries }

    let(:update_config) { FactoryBot.create(:update_config, package_manager: "bundler") }
    let!(:bundler_registry) { FactoryBot.create(:registry, source: update_config.repo, name: "my-bundler") }
    let!(:bundler_registry2) { FactoryBot.create(:registry, source: update_config.repo, name: "other-bundler") }
    let!(:npm_registry) { FactoryBot.create(:registry, :npm_and_yarn, source: update_config.repo, name: "my-npm") }

    it "returns compatible registries when #all_registries" do
      update_config.update(all_registries: true)
      expect(registries).to eq([bundler_registry, bundler_registry2])
    end

    it "returns no registries when #update_config_registries is empty" do
      update_config.update(all_registries: false)
      expect(registries).to be_empty
    end

    it "returns registries named by #update_config_registries" do
      update_config.update(all_registries: false)
      UpdateConfigRegistry.create(update_config: update_config, registry_name: "my-bundler")
      expect(registries).to eq([bundler_registry])
    end
  end

  describe "#manifest_directories" do
    context "when `directory` is set" do
      it "returns a Directories object including the directory" do
        directory = "/my-directory"
        update_config = build_stubbed(:update_config, directory: directory, directories: nil)

        expect(update_config.manifest_directories).to be_a Directories
        expect(update_config.manifest_directories).to include(directory)
      end

      it "doesn't consider `directories`" do
        directory = "/my-directory"
        directories = %w(/her-directory /his-directory)
        update_config = build_stubbed(:update_config, directory: directory, directories: directories)

        expect(update_config.manifest_directories).to include(directory)
        expect(update_config.manifest_directories).not_to include(directories)
      end
    end

    context "when `directories` is set" do
      it "returns a Directories object including the directories" do
        directories = %w(/yellow-pages /white-pages)
        update_config = build_stubbed(:update_config, directories: directories, directory: nil)

        expect(update_config.manifest_directories).to be_a Directories
        expect(update_config.manifest_directories).to include(*directories)
      end
    end
  end

  describe "#find_registry_by" do
    subject(:update_config) { FactoryBot.create(:update_config) }

    it "returns a match" do
      rubygems_registry = FactoryBot.create(:registry, :rubygems_server, source: update_config.repo, name: "gemfury")
      update_config.update_config_registries.create!(registry_name: "gemfury")

      result = subject.find_registry_by(type: :rubygems_server, host: "gem.fury.io")

      expect(result).to eq(rubygems_registry)
    end

    it "returns nil when a match is not found" do
      FactoryBot.create(:registry, :docker, source: update_config.repo, name: "my-docker")
      update_config.update_config_registries.create!(registry_name: "my-docker")

      result = subject.find_registry_by(type: :rubygems_server, host: "gem.fury.io")

      expect(result).to be_nil
    end
  end

  describe "#accessible_github_repo_ids" do
    context "when repository_access is allowed" do
      let(:account) do
        create(:account, github_login: "kyoto")
      end

      let!(:repository_access) do
        create(:repository_access, account: account)
      end

      let(:update_config) do
        repo = create(:repo, account: account)
        create(:update_config, repo: repo, package_manager: "go_modules")
      end

      let(:repo_ids) { update_config.accessible_github_repo_ids }

      it "includes only the current repo id and the selected repo ids" do
        expect(repo_ids).to contain_exactly(
          update_config.repo.github_id, repository_access.github_id,
        )
      end
    end

    context "when repository_access includes the target repo" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let!(:repository_access) do
        FactoryBot.create(:repository_access, account_id: account.id)
      end

      let(:repo) do
        FactoryBot.create(
          :repo,
          account_id: account.id,
          github_id: repository_access.github_id
        )
      end

      let(:update_config) do
        FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "go_modules"
        )
      end

      let(:repo_ids) { update_config.accessible_github_repo_ids }

      it "includes only the current repo id" do
        expect(repo_ids).to contain_exactly(repo.github_id)
      end
    end

    context "when repository_access is not allowed" do
      let(:account) do
        FactoryBot.create(
          :account,
          github_login: "kyoto"
        )
      end

      let!(:repository_access) do
        FactoryBot.create(:repository_access, account_id: account.id)
      end

      let(:repo) do
        FactoryBot.create(
          :repo,
          account_id: account.id,
          github_id: repository_access.github_id
        )
      end

      let(:update_config) do
        FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "bundler"
        )
      end

      let(:repo_ids) { update_config.accessible_github_repo_ids }

      it "does not include additional repo ids" do
        expect(repo_ids).to contain_exactly(repo.github_id)
      end
    end

    context "with jit accessed internal repos" do
      before do
        redis.sadd(update_config.jit_accessed_internal_repos_key, [1, 2, 3])
      end

      it "includes the jit accessed internal repo ids" do
        expect(update_config.accessible_github_repo_ids).to contain_exactly(update_config.repo.github_id, 1, 2, 3)
      end
    end

    context "when the access level is not set" do
      let(:repo) do
        account = FactoryBot.create(
          :account,
          github_login: "takayama"
        )

        FactoryBot.create(:repo, account_id: account.id)
      end

      let(:update_config) do
        FactoryBot.create(
          :update_config,
          repo_id: repo.id,
          package_manager: "go_modules"
        )
      end

      let(:repo_ids) { update_config.accessible_github_repo_ids }

      it "includes only the current repo id" do
        expect(repo_ids).to eq([repo.github_id])
      end
    end
  end

  describe "#accessible_github_repos" do
    let(:account) { create(:account) }

    let(:repo) { create(:repo, account: account) }
    let(:update_config) { create(:update_config, repo: repo, package_manager: PackageManagers::GO_MODULES) }

    let(:repository_access) { create(:repository_access, account: account) }
    let(:accessible_repo) { create(:repo, account: account, github_id: repository_access.github_id) }

    it "includes the update config's repo and the account's accessible repositories" do
      expected_repos = [repo, accessible_repo]
      expect(update_config.accessible_github_repos).to match_array(expected_repos)
    end

    it "does not include repositories that dependabot-api does not have records for" do
      accessible_repo.destroy!
      expect(update_config.accessible_github_repos).to contain_exactly(repo)
    end
  end

  describe "#jit_accessed_internal_github_repo_ids" do
    it "returns an empty array when no repos are set" do
      expect(update_config.jit_accessed_internal_github_repo_ids).to eq([])
    end

    it "returns an array of repo ids when they are set" do
      repo_ids = [1, 2, 3]
      redis.sadd(update_config.jit_accessed_internal_repos_key, repo_ids)
      expect(update_config.jit_accessed_internal_github_repo_ids).to eq(repo_ids)
    end
  end

  describe "#add_jit_accessed_internal_github_repo_ids" do
    before do
      repo_ids = [1, 2, 3]
      redis.sadd(update_config.jit_accessed_internal_repos_key, repo_ids)
    end

    it "sets the repo ids if a list doesn't already exist" do
      redis.del(update_config.jit_accessed_internal_repos_key)

      update_config.add_jit_accessed_internal_github_repo_ids([4, 5])
      expect(update_config.jit_accessed_internal_github_repo_ids).to contain_exactly(4, 5)
    end

    it "adds the repo ids to the existing list" do
      new_repo_ids = [4, 5]
      update_config.add_jit_accessed_internal_github_repo_ids(new_repo_ids)
      expect(update_config.jit_accessed_internal_github_repo_ids).to contain_exactly(1, 2, 3, 4, 5)
    end

    it "does not add duplicates" do
      new_repo_ids = [2, 3, 4, 5]
      update_config.add_jit_accessed_internal_github_repo_ids(new_repo_ids)
      expect(update_config.jit_accessed_internal_github_repo_ids).to contain_exactly(1, 2, 3, 4, 5)
    end
  end

  describe "#remove_jit_accessed_internal_github_repo_ids" do
    before do
      repo_ids = [1, 2, 3]
      redis.sadd(update_config.jit_accessed_internal_repos_key, repo_ids)
    end

    it "removes the repo ids from the list" do
      update_config.remove_jit_accessed_internal_github_repo_ids(2)
      expect(update_config.jit_accessed_internal_github_repo_ids).to contain_exactly(1, 3)
    end
  end

  describe "#audit_log" do
    subject(:update_config) do
      FactoryBot.create(:update_config, repo: repo)
    end

    let(:account) { FactoryBot.create(:account) }
    let(:repo) do
      FactoryBot.create(:repo, account: account, config_file_path: ".github/dependabot.yml")
    end

    let(:expected_repo_tags) do
      {
        account_id: repo.account.id,
        "gh.owner.id": repo.account.github_id,
        repository_id: repo.id,
        "gh.repo.id": repo.github_id,
        "gh.repo.visibility": "private",
        repository_using_config_file: true,
        nwo: repo.nwo,
        will_pause_at: repo.will_pause_at,
        paused_at: repo.paused_at,
      }
    end

    let(:expected_config_tags) do
      {
        context: "update-config",
        "gh.dependabot_api.update_config.id": update_config.id,
        update_config_version_updates_enabled: true,
      }
    end

    let(:expected_context_tags) do
      [
        expected_repo_tags,
        expected_config_tags,
      ].reduce(:merge)
    end

    before do
      allow(Dependabot::Logger).to receive(:info)
      allow(Dependabot::Logger).to receive(:log_context).and_call_original
      allow(Activity::PauseManager).to receive(:handle_activity_log_event)
    end

    it "writes a structured info log of the event to the repository topic" do
      update_config.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:info).with(
        {
          activity_log_event: "update-config.event-a",
          foo: "bar",
        }
      )
    end

    it "add details of the repository and account to the context" do
      update_config.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Dependabot::Logger).to have_received(:log_context).
        with(expected_repo_tags.merge(expected_config_tags))
    end

    it "notifies the Activity::PauseManager of the event" do
      update_config.event_stream.record_event("event-a", tags: { foo: "bar" })

      expect(Activity::PauseManager).to have_received(:handle_activity_log_event).with(
        "update-config.event-a",
        expected_context_tags.merge({ foo: "bar" })
      )
    end
  end

  context "multi ecosystem relations" do
    describe "has_many :multi_ecosystem_siblings" do
      let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
      let(:update_config) { create(:update_config, :active, multi_ecosystem_config: multi_ecosystem_config) }

      it "returns the multi_ecosystem_config" do
        expect(update_config.multi_ecosystem_config).to eq(multi_ecosystem_config)
      end

      it "returns sibling update configs with the same multi_ecosystem_config_id" do
        sibling_update_config = create(:update_config, :active, multi_ecosystem_config: multi_ecosystem_config)

        expect(update_config.multi_ecosystem_siblings).to contain_exactly(update_config, sibling_update_config)
      end

      it "does not include update configs with a different multi_ecosystem_config_id" do
        unrelated_update_config = create(:update_config)

        expect(update_config.multi_ecosystem_siblings).not_to include(unrelated_update_config)
      end
    end
  end

  describe "#update_next_enqueue_at!" do
    subject(:update_next_enqueue_at!) { update_config.update_next_enqueue_at! }

    let(:update_config) do
      FactoryBot.create(:update_config, update_schedule_cron_expression: cron_expression)
    end
    let(:cron_expression) { "0 0 * * *" }

    it "updates the next_enqueue_at" do
      freeze_time do
        expected_time = Fugit.parse_cron(cron_expression).next_time.utc
        update_next_enqueue_at!
        expect(update_config.reload.next_enqueue_at).to eq(expected_time)
      end
    end

    context "when the cron expression is invalid" do
      let(:cron_expression) { "invalid" }

      it "does not update the next_enqueue_at" do
        expect { update_next_enqueue_at! }.not_to change { update_config.reload.next_enqueue_at }
      end

      it "clears out an existing next_enqueue_at value" do
        update_config.update!(next_enqueue_at: 1.day.from_now)
        expect { update_next_enqueue_at! }.to change { update_config.reload.next_enqueue_at }.to(nil)
      end
    end

    context "when the config is deleted" do
      let(:update_config) do
        FactoryBot.create(:update_config, :deleted, update_schedule_cron_expression: cron_expression)
      end

      it "does not update the next_enqueue_at" do
        expect { update_next_enqueue_at! }.not_to change { update_config.reload.next_enqueue_at }
      end
    end
  end

  describe "#current_state" do
    it "is set to initial state on new records" do
      update_config = build(:update_config)
      expect(update_config.attributes["current_state"]).to eq(UpdateConfigStateMachine.initial_state)
    end

    it "is not set to initial state on existing records" do
      update_config = create(:update_config, :active)

      loaded_from_db = described_class.find(update_config.id)
      expect(loaded_from_db.attributes["current_state"]).to eq("active")
    end

    it "is validated to be a known update config state machine state" do
      update_config.current_state = "nonexistent_state"
      expect(update_config).not_to be_valid
    end
  end

  describe ".in_state" do
    it "uses the current_state column" do
      # create configs with different states recorded in transition history
      # and the current_state column
      rate_limited_update_config = create(:update_config).tap { |config| config.update!(current_state: :rate_limited) }
      active_update_config = create(:update_config).tap { |config| config.update!(current_state: :active) }

      results = described_class.in_state(:rate_limited).to_a

      expect(results).to include(rate_limited_update_config)
      expect(results).not_to include(active_update_config)
    end
  end

  describe ".not_in_state" do
    it "uses the current_state column" do
      # create configs with different states recorded in transition history
      # and the current_state column
      rate_limited_update_config = create(:update_config).tap { |config| config.update!(current_state: :rate_limited) }
      active_update_config = create(:update_config).tap { |config| config.update!(current_state: :active) }

      results = described_class.not_in_state(:rate_limited).to_a

      expect(results).to include(active_update_config)
      expect(results).not_to include(rate_limited_update_config)
    end
  end
end
