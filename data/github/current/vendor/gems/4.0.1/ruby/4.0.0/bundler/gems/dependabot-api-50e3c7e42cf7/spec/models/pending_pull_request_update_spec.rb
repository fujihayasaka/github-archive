# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingPullRequestUpdate, type: :model do
  subject(:pending_pull_request_update) do
    pr_update = FactoryBot.create(:pending_pull_request_update)
    pr_update.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(updated_files.to_json)),
      filename: pr_update.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr_update
  end

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
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

  describe "#updated_dependency_files" do
    subject(:updated_dependency_files) do
      pending_pull_request_update.updated_dependency_files
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
end
