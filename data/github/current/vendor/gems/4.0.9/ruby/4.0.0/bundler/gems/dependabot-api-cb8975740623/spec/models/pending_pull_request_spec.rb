# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingPullRequest, type: :model do
  subject(:pending_pull_request) do
    pr = FactoryBot.create(
      :pending_pull_request,
      updated_dependency_details: updated_dependency_hashes,
    )
    pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(updated_files.to_json)),
      filename: pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr
  end

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  let(:updated_dependency_hashes) do
    [
      {
        "name" => name,
        "version" => version,
        "previous_version" => previous_version,
        "requirements" => requirements,
        "previous_requirements" => previous_requirements,
        "package_manager" => "bundler",
      },
    ]
  end
  let(:name) { "business" }
  let(:version) { "1.8.0" }
  let(:previous_version) { "1.7.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.7.0", groups: [], source: nil }]
  end
  let(:updated_files) do
    [
      {
        "content" => "things1",
        "name" => "Gemfile",
        "directory" => "/",
        "type" => "file",
      },
      {
        "content" => "things2",
        "name" => "Gemfile.lock",
        "directory" => "/",
        "type" => "file",
      },
    ]
  end

  describe "#message_data" do
    it "returns a hash of message data fields" do
      pending_pull_request.message_data = { "pr_title" => "x", "pr_body" => "y", "commit_message" => "z" }

      expect(pending_pull_request.message_data).to be_a(Hash)
      expect(pending_pull_request.message_data["pr_title"]).to eq("x")
      expect(pending_pull_request.message_data["pr_body"]).to eq("y")
      expect(pending_pull_request.message_data["commit_message"]).to eq("z")
    end

    it "returns an empty hash if PendingPullRequest has no encrypted_message_data_blob attachment" do
      expect(pending_pull_request.message_data).to eq({})
    end
  end

  describe "#updated_dependencies" do
    subject(:updated_dependencies) { pending_pull_request.updated_dependencies }

    it "is an array of correct Dependabot::Dependency objects" do
      expect(updated_dependencies).to be_a(Array)
      expect(updated_dependencies.count).to eq(1)
      expect(updated_dependencies.first).to be_a(Dependabot::Dependency)
      expect(updated_dependencies.first.name).to eq(name)
      expect(updated_dependencies.first.requirements).to eq(requirements)
    end

    context "with a removed transitive dependency" do
      let(:updated_dependency_hashes) do
        [
          {
            "name" => name,
            "previous_version" => previous_version,
            "requirements" => [],
            "previous_requirements" => [],
            "package_manager" => "bundler",
            "removed" => true,
          },
          {
            "name" => "parent_dep",
            "previous_version" => previous_version,
            "version" => version,
            "requirements" => [],
            "previous_requirements" => [],
            "package_manager" => "bundler",
          },
        ]
      end

      it "is an array of correct Dependabot::Dependency objects" do
        expect(updated_dependencies).to be_a(Array)
        expect(updated_dependencies.count).to eq(2)
        expect(updated_dependencies.first).to be_a(Dependabot::Dependency)
        expect(updated_dependencies.first.name).to eq(name)
        expect(updated_dependencies.first.removed?).to eq(true)
        expect(updated_dependencies.second).to be_a(Dependabot::Dependency)
        expect(updated_dependencies.second.name).to eq("parent_dep")
        expect(updated_dependencies.second.removed?).to eq(false)
      end
    end
  end

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) do
      pending_pull_request.updated_dependency_files
    end

    it "is an array of correct Dependabot::DependencyFile objects" do
      expect(updated_dependency_files).to be_a(Array)
      expect(updated_dependency_files.count).to eq(2)
      expect(updated_dependency_files.first).to be_a(Dependabot::DependencyFile)
      expect(updated_dependency_files.first.name).to eq("Gemfile")
      expect(updated_dependency_files.first.content).to eq("things1")
    end

    context "with optional deleted and content_encoding attributes" do
      let(:updated_files) do
        [
          {
            "content" => "things1",
            "name" => "Gemfile",
            "directory" => "/",
            "type" => "file",
            "deleted" => true,
            "operation" => "delete",
            "content_encoding" => "utf-8",
          },
          {
            "content" => "things2",
            "name" => "Gemfile.lock",
            "directory" => "/",
            "type" => "file",
            "deleted" => false,
            "operation" => "update",
            "content_encoding" => "base64",
          },
        ]
      end

      it "is an array of correct Dependabot::DependencyFile objects" do
        expect(updated_dependency_files.first.deleted).to eq(true)
        expect(updated_dependency_files.last.content_encoding).to eq("base64")
      end
    end
  end

  describe "#dependency_group" do
    context "when this is for a grouped update" do
      it "returns a DependencyGroup" do
        pending_pull_request = create(:pending_pull_request, grouped_update: true)

        expect(pending_pull_request.dependency_group).to be_a(DependencyGroup)
      end

      it "returns the associated DependencyGroup" do
        dependency_group = create(:dependency_group)
        pending_pull_request = create(:pending_pull_request, dependency_group: dependency_group, grouped_update: true)

        expect(pending_pull_request.dependency_group).to eq(dependency_group)
      end

      it "returns an in-memory DependencyGroup with the package manager's name if none is associated" do
        pending_pull_request = create(:pending_pull_request, grouped_update: true)

        expect(pending_pull_request.dependency_group.name).to eq(pending_pull_request.update_job.package_manager)
        expect(pending_pull_request.dependency_group).not_to be_persisted
      end
    end
  end

  describe "#current_state" do
    it "is set to initial state on new records" do
      pending_pull_request = build(:pending_pull_request)
      expect(pending_pull_request.attributes["current_state"]).to eq(PendingPullRequestStateMachine.initial_state)
    end

    it "is not set to initial state on existing records" do
      pending_pull_request = create(:pending_pull_request, :created)

      loaded_from_db = described_class.find(pending_pull_request.id)
      expect(loaded_from_db.attributes["current_state"]).to eq("created")
    end

    it "is validated to be a known pending pull request state machine state" do
      pending_pull_request.current_state = "nonexistent_state"
      expect(pending_pull_request).not_to be_valid
    end
  end

  describe ".in_state" do
    it "uses the current_state column" do
      # create pending PRs with different states recorded in transition history
      # and the current_state column
      created_pending_pull_request = create(:pending_pull_request).tap { |pr| pr.update!(current_state: :created) }
      abandoned_pending_pull_request = create(:pending_pull_request).tap { |pr| pr.update!(current_state: :abandoned) }

      results = described_class.in_state(:created).to_a

      expect(results).to include(created_pending_pull_request)
      expect(results).not_to include(abandoned_pending_pull_request)
    end
  end

  describe ".not_in_state" do
    it "uses the current_state column" do
      # create pending PRs with different states recorded in transition history
      # and the current_state column
      created_pending_pull_request = create(:pending_pull_request).tap { |pr| pr.update!(current_state: :created) }
      abandoned_pending_pull_request = create(:pending_pull_request).tap { |pr| pr.update!(current_state: :abandoned) }

      results = described_class.not_in_state(:created).to_a

      expect(results).to include(abandoned_pending_pull_request)
      expect(results).not_to include(created_pending_pull_request)
    end
  end
end
