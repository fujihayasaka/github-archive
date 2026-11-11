# frozen_string_literal: true

require "rails_helper"

RSpec.describe PrioritizedJobs::CreatePullRequestOnGitHub do
  include ActiveJob::TestHelper

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  let(:account) { create(:account, :dependabot, :active) }
  let(:repo) { create(:repo, :bump_test, account: account) }
  let(:update_config) { create(:update_config, :rate_limited, repo: repo) }
  let(:update_job) { create(:update_job, update_config: update_config) }

  let(:pending_pr) do
    pr = PendingPullRequest.create!(
      update_job: update_job,
      updated_dependency_details: [updated_dependency_hash],
      sort_key: 1,
    )
    pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
      filename: pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr
  end

  let(:updated_dependency_hash) do
    {
      "name" => name,
      "version" => version,
      "previous_version" => previous_version,
      "requirements" => requirements,
      "previous_requirements" => previous_requirements,
      "package_manager" => "bundler",
    }
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

  let(:files) do
    [
      {
        "content" => "things1",
        "name" => "Gemfile",
        "directory" => "/",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
      },
      {
        "content" => "things2",
        "name" => "Gemfile.lock",
        "directory" => "/",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
      },
    ]
  end

  describe "::perform_later" do
    let(:perform_later) do
      described_class.perform_later(pending_pr: pending_pr)
    end

    UpdateJob::PULL_REQUEST_TRIGGER_TYPES_P1.each do |trigger|
      context "with a #{trigger} update job" do
        let(:update_job) { create(:update_job, update_config: update_config, trigger_type: trigger) }

        it "enqueues a job in the p1 queue" do
          expect { perform_later }.
            to have_enqueued_job(PrioritizedJobs::CreatePullRequestOnGitHub::High).
            on_queue("create_pull_request_p1").
            with(pending_pr: pending_pr)
        end
      end
    end

    UpdateJob::PULL_REQUEST_TRIGGER_TYPES_P2.each do |trigger|
      context "with a #{trigger} update job" do
        let(:update_job) { create(:update_job, update_config: update_config, trigger_type: trigger) }

        it "enqueues a job in the p2 queue" do
          expect { perform_later }.
            to have_enqueued_job(PrioritizedJobs::CreatePullRequestOnGitHub::Default).
            on_queue("create_pull_request_p2").
            with(pending_pr: pending_pr)
        end
      end
    end
    UpdateJob::PULL_REQUEST_TRIGGER_TYPES_P3.each do |trigger|
      context "with a #{trigger} update job" do
        let(:update_job) { create(:update_job, update_config: update_config, trigger_type: trigger) }

        it "enqueues a job in the p3 queue" do
          expect { perform_later }.
            to have_enqueued_job(PrioritizedJobs::CreatePullRequestOnGitHub::Low).
            on_queue("create_pull_request_p3").
            with(pending_pr: pending_pr)
        end
      end
    end
  end
end
