# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreatePullRequestOnDependabot do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pending_pr:, github_pull_request:) }

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  let(:pending_pr) do
    pr = PendingPullRequest.create!(
      update_job: update_job,
      updated_dependency_details: updated_dependency_details,
      sort_key: 0,
    )
    pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
      filename: pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr.message_data = message_data
    pr
  end
  let(:account) { create(:account, :dependabot, :active) }
  let(:repo) { create(:repo, :bump_test, account: account) }
  let(:update_config) do
    create(:update_config, :rate_limited,
           repo: repo)
  end
  let(:sha) { "0123456789012345678901234567890123456789" }
  let(:update_job) { create(:update_job, update_config: update_config, github_request_id: nil, base_commit_sha: sha) }
  let(:updated_dependency_details) { [updated_dependency_hash] }
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
        "directory" => "/test",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
        "content_encoding" => "utf-8",
        "deleted" => false,
        "mode" => "file",
      },
      {
        "content" => "things2",
        "name" => "Gemfile.lock",
        "directory" => "/test",
        "type" => "file",
        "operation" => "update",
        "support_file" => false,
        "content_encoding" => "utf-8",
        "deleted" => false,
        "mode" => "file",
      },
    ]
  end
  let(:message_data) do
    {
      commit_message: "some commit message",
      pr_title: "some pr title",
      pr_body: "some pr body",
    }
  end
  let(:github_pull_request) do
    MonolithTwirp::Dependabot::PullRequests::V1::PullRequest.new(
      github_number: 2,
      head_sha: "a" * 40,
      base_sha: "b" * 40
    ).to_h
  end

  before do
    allow(update_job).to receive(:increment_metric).and_call_original
  end

  describe "#perform" do
    context "when the `PullRequest` does not exist" do
      it "creates a PullRequest" do
        expect { job.perform_now }.to change(PullRequest, :count).by(1)

        pull_request = PullRequest.last
        expect(pull_request.github_number).to eq(github_pull_request[:github_number])
        expect(pull_request.current_state).to eq("up_to_date")
        expect(pull_request.head_commit_sha).to eq(github_pull_request[:head_sha])
        expect(pull_request.dependabot_commit_sha).to eq(github_pull_request[:head_sha])
        expect(pull_request.base_commit_sha).to eq(github_pull_request[:base_sha])
        expect(pull_request.multiple_dependencies).to eq(pending_pr.updated_dependencies.count > 1)
        expect(pull_request.grouped_update).to eq(pending_pr.dependency_group.present?)
        expect(pull_request.dependency_group).to eq(pending_pr.dependency_group)
        expect(pull_request.affected_directories).
          to eq(pending_pr.updated_dependency_files.map(&:directory).uniq.sort)
      end

      it "creates UpdatedDependencies" do
        expect { job.perform_now }.to change(UpdatedDependency, :count).by(1)

        updated_dependency = UpdatedDependency.last
        expect(updated_dependency.pull_request).to eq(PullRequest.last)
        expect(updated_dependency.name).to eq(name)
        expect(updated_dependency.version).to eq(version)
        expect(updated_dependency.previous_version).to eq(previous_version)
        expect(updated_dependency.requirements.map { |req| req.transform_keys(&:to_sym) }).to eq(requirements)
        expect(updated_dependency.previous_requirements.map do |req|
          req.transform_keys(&:to_sym)
        end).to eq(previous_requirements)
        expect(updated_dependency.package_manager).to eq("bundler")
      end

      it "marks the pending PR as created" do
        expect { job.perform_now }.to change(pending_pr, :current_state).from("pending").to("created")
      end

      it "enqueues a ci status job" do
        expect { job.perform_now }.to have_enqueued_job(UpdatePullRequestCiStatusJob)
      end

      it "closes outdated pull requests" do
        close_outdated_pull_requests = instance_double(CloseOutdatedPullRequests, run: nil)
        allow(CloseOutdatedPullRequests).to receive(:new).with(pull_request: an_instance_of(PullRequest)).
          and_return(close_outdated_pull_requests)

        job.perform_now

        expect(close_outdated_pull_requests).to have_received(:run)
      end

      it "records metrics for happy path" do
        job.perform_now

        expect(update_job).to have_received(:increment_metric).with("create_pull_request_on_dependabot.attempt")
        expect(update_job).to have_received(:increment_metric).with("create_pull_request_on_dependabot.success")
      end
    end

    context "when a `PullRequest` already exists" do
      before do
        create(:pull_request, repo: repo, github_number: github_pull_request[:github_number])
      end

      it "does not create a new record" do
        expect { job.perform_now }.
          not_to change(PullRequest, :count)
      end

      it "does not update dependencies" do
        expect { job.perform_now }.
          not_to change(UpdatedDependency, :count)
      end
    end

    it "records end to end timing" do
      expect(MetricsClient).to receive(:timing)

      job.perform_now
    end

    context "when a `PullRequest` fails to create" do
      before do
        allow(PullRequest).to receive(:create!).and_raise(error_with_record)
      end

      it "doesn't cause the job to be re-enqueued" do
        expect { job.perform_now }.
          not_to have_enqueued_job(self.class)
      end

      it "adds an error to the update job" do
        job.perform_now

        expect(update_job.last_error.error_type).to eq("internal_pull_request_creation_failure")
      end

      it "reports the failures" do
        expect(Dependabot::Logger).
          to receive(:error).with(hash_including(msg: "Dependabot failed to create a PullRequest"))
        expect(MetricsClient).
          to receive(:increment).with("create_pull_request_on_dependabot.failure")

        job.perform_now
      end

      it "records metrics when there's an exception" do
        allow(PullRequest).to receive(:create!).and_raise(StandardError)

        expect { job.perform_now }.to raise_error(StandardError)

        expect(update_job).to have_received(:increment_metric).with("create_pull_request_on_dependabot.attempt")
        expect(update_job).to have_received(:increment_metric).
          with("create_pull_request_on_dependabot.error", tags: { error: "StandardError" })
      end
    end

    def error_with_record
      invalid_pull_request = PullRequest.new
      # trigger validation
      invalid_pull_request.valid?
      ActiveRecord::RecordInvalid.new(invalid_pull_request)
    end
  end
end
