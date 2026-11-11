# frozen_string_literal: true

require "rails_helper"

RSpec.describe Routes::UpdateJobs::CreatePullRequest do
  subject(:instance) { described_class.new(context) }

  let(:context) { { request: request, update_job: update_job } }
  let(:request) { instance_double(ActionDispatch::Request, params: params) }
  let(:params) { params_hash.deep_symbolize_keys }
  let(:params_hash) do
    {
      data: {
        "commit-message" => commit_message,
        "pr-title" => pr_title,
        "pr-body" => pr_body,
        "updated-dependency-files" => files,
        "base-commit-sha" => "sha",
        "dependencies" => [
          {
            "name" => name,
            "version" => version,
            "previous-version" => previous_version,
            "requirements" => requirements,
            "directory" => directory,
            "previous-requirements" => previous_requirements,
          },
        ],
      },
    }
  end
  let(:commit_message) { "some commit message" }
  let(:pr_title) { "some pr title" }
  let(:pr_body) { "some pr body" }
  let(:name) { "business" }
  let(:version) { "1.8.0" }
  let(:previous_version) { "1.7.0" }
  let(:requirements) do
    [{ file: "file", requirement: "~> 1.8.0", groups: [], source: nil }]
  end
  let(:directory) { "/" }
  let(:previous_requirements) do
    [{ file: "file", requirement: "~> 1.7.0", groups: [], source: nil }]
  end
  let(:files) do
    [
      {
        content: "some things",
        name: "Gemfile",
        directory: directory,
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
      },
      {
        content: "more things",
        name: "Gemfile.lock",
        directory: directory,
        type: "file",
        support_file: false,
        content_encoding: "utf-8",
        deleted: false,
        operation: "update",
      },
    ]
  end

  let(:create_pr_job) { PrioritizedJobs::CreatePullRequestOnGitHub::Default }

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  shared_examples "creates a new PR" do
    it { is_expected.to respond_with_status(204) }

    it "enqueues a job to create a new PR for repo" do
      expect { instance.call }.to(
        have_enqueued_job(create_pr_job).with do |args|
          pending_pr = args.fetch(:pending_pr)
          expect(pending_pr).to be_persisted
          expect(pending_pr.message_data).
            to eq({
              commit_message: commit_message,
              pr_title: pr_title,
              pr_body: pr_body,
            }.with_indifferent_access)
          expect(pending_pr.updated_dependency_files.map(&:to_h)).
            to eq(files.map(&:stringify_keys))
          expect(pending_pr.updated_dependency_details).to eq(
            [
              {
                "name" => name,
                "version" => version,
                "previous_version" => previous_version,
                "directory" => directory,
                "requirements" => requirements.map(&:stringify_keys),
                "previous_requirements" => previous_requirements.
                                           map(&:stringify_keys),
                "package_manager" => update_job.package_manager,
              },
            ]
          )
          expect(pending_pr).not_to be_grouped_update
        end
      )
    end
  end

  context "for an update job not targeting a specific dependency" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    include_examples "creates a new PR"

    context "with a rate-limited job" do
      context "that has created fewer than 5 PRs" do
        include_examples "creates a new PR"
      end

      context "that has created 5 pending PRs" do
        before do
          5.times do |i|
            PendingPullRequest.create!(
              update_job: update_job,
              updated_dependency_details: [
                {
                  "name" => "unrelated_dep",
                  "version" => "1.8.0",
                  "previous_version" => "1.3.0",
                  "requirements" => [],
                  "previous_requirements" => [],
                },
              ],
              sort_key: i + 1,
            )
          end
        end

        it { is_expected.to respond_with_status(204) }

        context "but this PR fixes a security vulnerability" do
          before do
            advisory = FactoryBot.build(
              :github_security_advisory,
              package_manager: update_job.package_manager,
              dependency_name: name,
              patched_versions: [version],
            )
            allow(GitHubSecurityAdvisory).to receive(:fetch).and_return([advisory])
          end

          include_examples "creates a new PR"
        end

        context "when there's a race" do
          before do
            allow(PendingPullRequest).
              to receive(:where).
              and_return([1, 2, 3, 4], [1, 2, 3, 4, 5])
          end

          it { is_expected.to respond_with_status(204) }
        end
      end

      context "that has created 4 pending PRs" do
        before do
          4.times do |i|
            PendingPullRequest.create!(
              update_job: update_job,
              updated_dependency_details: [
                {
                  "name" => "unrelated_dep",
                  "version" => "1.8.0",
                  "previous_version" => "1.3.0",
                  "requirements" => [],
                  "previous_requirements" => [],
                },
              ],
              sort_key: i + 1,
            )
          end
        end

        context "when there's a race" do
          before do
            allow(PendingPullRequest).
              to receive(:where).
              and_return([1, 2, 3], [1, 2, 3, 4])
          end

          include_examples "creates a new PR"
        end
      end
    end

    context "with an active job" do
      before { update_job.update_config.transition_to!(:active) }

      context "that has created 5 PRs" do
        before do
          FactoryBot.create_list(
            :pull_request, 5,
            update_job: update_job,
            dependencies: [
              {
                "name" => "unrelated_dep",
                "version" => "1.8.0",
                "previous_version" => "1.3.0",
                "requirements" => [],
                "previous_requirements" => [],
              },
            ],
          )
        end

        include_examples "creates a new PR"
      end
    end
  end

  context "for a PR that removes a transitive dependency" do
    let(:update_job) { FactoryBot.create(:update_job, :processing, :security) }

    let(:params_hash) do
      {
        data: {
          "commit-message" => commit_message,
          "pr-title" => pr_title,
          "pr-body" => pr_body,
          "updated-dependency-files" => files,
          "base-commit-sha" => "sha",
          "dependencies" => [
            {
              "name" => name,
              "previous-version" => previous_version,
              "requirements" => [],
              "previous-requirements" => [],
              "removed" => true,
            },
            {
              "name" => "parent_dep",
              "version" => "1.8.0",
              "previous-version" => "1.3.0",
              "requirements" => [],
              "previous-requirements" => [],
            },
          ],
        },
      }
    end

    it "enqueues a job to create a new PR for repo" do
      expect { instance.call }.to(
        have_enqueued_job(create_pr_job).with do |args|
          pending_pr = args.fetch(:pending_pr)
          expect(pending_pr).to be_persisted
          expect(pending_pr.message_data).
            to eq({
              commit_message: commit_message,
              pr_title: pr_title,
              pr_body: pr_body,
            }.with_indifferent_access)
          expect(pending_pr.updated_dependency_files.map(&:to_h)).
            to eq(files.map(&:stringify_keys))
          expect(pending_pr.updated_dependency_details).to eq(
            [
              {
                "name" => name,
                "previous_version" => previous_version,
                "requirements" => [],
                "previous_requirements" => [],
                "package_manager" => update_job.package_manager,
                "removed" => true,
              },
              {
                "name" => "parent_dep",
                "version" => "1.8.0",
                "previous_version" => "1.3.0",
                "requirements" => [],
                "previous_requirements" => [],
                "package_manager" => update_job.package_manager,
              },
            ]
          )
          expect(pending_pr).not_to be_grouped_update
        end
      )
    end
  end

  context "for a PR that is the result of a grouped update with a Dependency Group object" do
    let(:dependency_group_name) { "my-dependencies" }
    let(:update_job) { FactoryBot.create(:update_job, :processing, :version_update) }

    let(:params_hash) do
      {
        data: {
          "commit-message" => commit_message,
          "pr-title" => pr_title,
          "pr-body" => pr_body,
          "updated-dependency-files" => files,
          "base-commit-sha" => "sha",
          "dependencies" => [
            {
              "name" => name,
              "version" => version,
              "previous-version" => previous_version,
              "requirements" => requirements,
              "previous-requirements" => previous_requirements,
            },
          ],
          "grouped-update" => true,
          "dependency-group" => {
            "name" => dependency_group_name,
          },
        },
      }
    end

    # FIXME: We should require Dependency Group ids to exist
    #
    # Until we have logical deletion, there is no guarantee a Dependency Group
    # will exist when a job finishes.
    #
    # See: https://github.com/github/dependabot-updates/issues/3907
    context "when no Dependency Group with that id exists" do
      it "creates a group_update pending pull request without a Dependency Group and enqueues a job" do
        expect { instance.call }.to change(PendingPullRequest, :count).from(0).to(1)

        pending_pr = PendingPullRequest.last

        expect(pending_pr).to be_grouped_update
        expect(pending_pr.dependency_group_id).to be_nil
        expect(create_pr_job).to have_been_enqueued.with(pending_pr: pending_pr).once
      end
    end

    context "when a Dependency Group with that id exists and belongs to the current Update Config" do
      let!(:dependency_group) do
        FactoryBot.create(:dependency_group,
                          name: dependency_group_name,
                          update_config: update_job.update_config)
      end

      it "creates a group_update pending pull request with a Dependency Group and enqueues a job" do
        expect { instance.call }.to change(PendingPullRequest, :count).from(0).to(1)

        pending_pr = PendingPullRequest.last

        expect(pending_pr).to be_grouped_update
        expect(pending_pr.dependency_group).to eql(dependency_group)
        expect(create_pr_job).to have_been_enqueued.with(pending_pr: pending_pr).once
      end
    end

    context "when a Dependency Group with that id exists, but it belongs to another Update Config" do
      before do
        FactoryBot.create(:dependency_group,
                          id: dependency_group_name,
                          name: "my-dependencies")
      end

      it "creates a group_update pending pull request without an associated group and enqueues a job" do
        expect { instance.call }.to change(PendingPullRequest, :count).from(0).to(1)

        pending_pr = PendingPullRequest.last

        expect(pending_pr).to be_grouped_update
        expect(pending_pr.dependency_group_id).to be_nil
        expect(create_pr_job).to have_been_enqueued.with(pending_pr: pending_pr).once
      end
    end
  end

  context "for a PR that has a Dependency Group object but no grouped_update flag" do
    let(:dependency_group_name) { "my-dependencies" }
    let(:update_job) { FactoryBot.create(:update_job, :processing, :version_update) }

    let(:params_hash) do
      {
        data: {
          "commit-message" => commit_message,
          "pr-title" => pr_title,
          "pr-body" => pr_body,
          "updated-dependency-files" => files,
          "base-commit-sha" => "sha",
          "dependencies" => [
            {
              "name" => name,
              "version" => version,
              "previous-version" => previous_version,
              "requirements" => requirements,
              "previous-requirements" => previous_requirements,
            },
          ],
          "dependency-group" => {
            "name" => dependency_group_name,
          },
        },
      }
    end

    context "the DependencyGroup exists" do
      let!(:dependency_group) do
        FactoryBot.create(:dependency_group,
                          name: dependency_group_name,
                          update_config: update_job.update_config)
      end

      it "forces grouped_update to true due to the presence of the dependency-group and enqueues a job" do
        expect { instance.call }.to change(PendingPullRequest, :count).from(0).to(1)

        pending_pr = PendingPullRequest.last

        expect(pending_pr).to be_grouped_update
        expect(pending_pr.dependency_group).to eql(dependency_group)
        expect(create_pr_job).to have_been_enqueued.with(pending_pr: pending_pr).once
      end
    end

    context "the DependencyGroup does not exist" do
      it "sets grouped_update to true, but does not persist a dependency group and enqueues a job" do
        expect { instance.call }.to change(PendingPullRequest, :count).from(0).to(1)

        pending_pr = PendingPullRequest.last

        expect(pending_pr).to be_grouped_update
        expect(pending_pr.dependency_group_id).to be_nil
        expect(create_pr_job).to have_been_enqueued.with(pending_pr: pending_pr).once
      end
    end
  end

  context "For a PR when multi-ecosystem feature is not enabled" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, multi_ecosystem_config:) }
    let(:update_job) { create(:update_job, :processing, update_config:) }

    before do
      allow(update_job).to receive(:config_feature_enabled?).and_return(false)
    end

    it "enqueues the CreatePullRequest job" do
      expect(PrioritizedJobs::CreatePullRequestOnGitHub).to receive(
        :perform_later
      ).with(pending_pr: kind_of(PendingPullRequest))
      instance.call
    end
  end

  context "For a PR when multi_ecosystems feature is enabled" do
    let(:multi_ecosystem_config) { create(:multi_ecosystem_config) }
    let(:update_config) { create(:update_config, multi_ecosystem_config:) }
    let(:related_update_config) { create(:update_config, multi_ecosystem_config:) }
    let(:enqueue_scheduled_update_id) { "fixed-uuid" }
    let(:update_jobs) do
      [
        create(:update_job, :processing, update_config:, enqueue_scheduled_update_id:),
        create(:update_job, :processing, update_config: related_update_config, enqueue_scheduled_update_id:),
      ]
    end
    let(:context) { { request: request, update_job: update_jobs.last } }

    before do
      update_jobs.each do |update_job|
        allow(update_job).to receive(:config_feature_enabled?).and_return(false)
        allow(update_job).to receive(:config_feature_enabled?).with(:multi_ecosystems).and_return(true)
      end
    end

    it "does not enqueues the CreatePullRequest job" do
      expect(PrioritizedJobs::CreatePullRequestOnGitHub).not_to receive(
        :perform_later
      ).with(pending_pr: kind_of(PendingPullRequest))
      instance.call
    end
  end

  context "For an update targeting GitHub Actions workflow files from non-GitHub Actions ecosystem" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    let(:files) do
      [
        {
          content: "some workflow content",
          name: ".github/workflows/test.yml",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it "logs an error and returns a 400 status" do
      expect { instance.call }.not_to have_enqueued_job(create_pr_job)
      expect(instance).to respond_with_status(400)
    end
  end

  context "For an update targeting correct dependency files" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    let(:files) do
      [
        {
          content: "some workflow content",
          name: "Gemfile.lock",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it "enqueues CreatePullRequestJob" do
      expect { instance.call }.to have_enqueued_job(create_pr_job)
      expect(instance).not_to respond_with_status(400)
    end
  end

  context "For an update targeting Gemfile.jumpstart" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    let(:files) do
      [
        {
          content: "some workflow content",
          name: "Gemfile.jumpstart",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it "enqueues CreatePullRequestJob with jumpstart support file" do
      expect { instance.call }.to have_enqueued_job(create_pr_job)
      expect(instance).to respond_with_status(204)
    end
  end

  context "For an update targeting wrong dependency files for the package manager" do
    let(:update_job) { FactoryBot.create(:update_job, :processing) }

    let(:files) do
      [
        {
          content: "some workflow content",
          name: "requirements.txt",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it "does not enqueue job and returns 400" do
      expect { instance.call }.not_to have_enqueued_job(create_pr_job)
      expect(instance).to respond_with_status(400)
    end
  end

  context "For an update targeting invalid package manager" do
    let(:update_config) do
      update_config = FactoryBot.build(:update_config, package_manager: "foobar", required_instance_size: "small")
      allow(update_config).to receive(:valid?).and_return(true)
      update_config.save(validate: false)
      update_config
    end

    let(:update_job) do
      FactoryBot.create(:update_job, :processing, update_config: update_config)
    end

    let(:files) do
      [
        {
          content: "some workflow content",
          name: "foo.lock",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it "raises PackageManagerNotFound" do
      expect { instance.call }.to raise_error(DependencyFileAllowlist::PackageManagerNotFound)
    end
  end

  context "For a Gradle update with lock files" do
    let(:update_config) do
      update_config = FactoryBot.build(:update_config, package_manager: "gradle", required_instance_size: "small")
      allow(update_config).to receive(:valid?).and_return(true)
      update_config.save(validate: false)
      update_config
    end

    let(:update_job) do
      FactoryBot.create(:update_job, :processing, update_config: update_config)
    end

    let(:files) do
      [
        {
          content: "{}",
          name: "gradle.lockfile",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it { is_expected.to respond_with_status(204) }
  end

  context "For a NuGet update with lock files" do
    let(:update_config) do
      update_config = FactoryBot.build(:update_config, package_manager: "nuget", required_instance_size: "small")
      allow(update_config).to receive(:valid?).and_return(true)
      update_config.save(validate: false)
      update_config
    end

    let(:update_job) do
      FactoryBot.create(:update_job, :processing, update_config: update_config)
    end

    let(:files) do
      [
        {
          content: "{}",
          name: "packages.lock.json",
          directory: "/",
          type: "file",
          support_file: false,
          content_encoding: "utf-8",
          deleted: false,
          operation: "update",
        },
      ]
    end

    it { is_expected.to respond_with_status(204) }
  end
end
