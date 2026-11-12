# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestJob, type: :job do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  subject(:job) do
    described_class.new(
      update_job_id: update_job.id,
      pending_pull_request_update: pending_pull_request_update,
    )
  end

  def encrypt_temporary_file_blob(blob)
    token = Base64.strict_decode64(Prius.get(:temporary_file_encryption_key))
    encrypted_box = RbNaCl::SimpleBox.from_secret_key(token)

    Base64.strict_encode64(encrypted_box.encrypt(blob))
  end

  let!(:pending_pull_request_update) do
    pr = FactoryBot.create(
      :pending_pull_request_update,
      pull_request: pull_request,
      updated_base_commit_sha: commit_sha,
    )
    pr.encrypted_dependency_files_blob.attach(
      io: StringIO.new(encrypt_temporary_file_blob(files.to_json)),
      filename: pr.id,
      content_type: "application/octet-stream",
      identify: false,
    )
    pr
  end
  let(:repo) { FactoryBot.create(:repo, :active, github_id: 123) }
  let(:pull_request) { FactoryBot.create(:pull_request, :updating, repo: repo, github_number: 1) }
  let(:files) do
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
  let(:commit_sha) { "commitsha" }

  let(:expected_dependency_files) do
    [
      Dependabot::DependencyFile.new(
        content: "things1",
        name: "Gemfile",
        directory: "/",
        type: "file",
      ),
      Dependabot::DependencyFile.new(
        content: "things2",
        name: "Gemfile.lock",
        directory: "/",
        type: "file",
      ),
    ]
  end
  let(:dummy_pr_updater) { instance_double(UpdatePullRequest, run: nil) }
  let(:update_job) do
    FactoryBot.create(:update_job, :version_update, trigger_type: "rebase")
  end

  before do
    allow(UpdatePullRequest).to receive(:new).and_return(dummy_pr_updater)
  end

  it "delegates to the UpdatePullRequest action" do
    expect(UpdatePullRequest).
      to receive(:new).
      with(
        pull_request: pull_request,
        updated_dependency_files: instance_of(Array),
        new_base_commit_sha: "commitsha",
      ) do |args|
        expect(args[:updated_dependency_files].map(&:to_h)).
          to eq(expected_dependency_files.map(&:to_h))
      end.and_return(dummy_pr_updater)
    expect(dummy_pr_updater).to receive(:run)
    job.perform_now
  end

  it "deletes the pending_pull_request_update" do
    expect { job.perform_now }.
      to change(PendingPullRequestUpdate, :count).
      by(-1)
  end

  it "instruments success" do
    expect(MetricsClient).
      to receive(:count).
      with("update_pull_request.success", 1,
           tags: hash_including(grouped_update: false, trigger: "rebase"))

    job.perform_now
  end

  context "with updated_dependency_files that have expired on S3" do
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { github_url + "repositories/123" }
    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    before do
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_return("token")

      stub_request(:get, repo_url + "/pulls/1").
        to_return(status: 200, body: github_pull_request, headers: json_header)
      stub_request(:patch, repo_url + "/pulls/1").
        to_return(status: 200, body: github_pull_request, headers: json_header)
    end

    it "re-enqueues a rebase job" do
      allow(pending_pull_request_update).to receive(:updated_dependency_files).and_raise(
        ActiveStorage::FileNotFoundError
      )

      travel_to 2.days.from_now do
        expect { job.perform_now }.to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low)
        expect(MetricsClient).to have_received(:count).with(
          "update_pull_request.rebase_reenqueued", 1,
          tags: hash_including(grouped_update: false, group_count: 0)
        )
      end
    end

    it "instruments the expired files" do
      expect(MetricsClient).
        to receive(:count).
        with("update_pull_request.expired_files", 1,
             tags: hash_including(grouped_update: false, trigger: "rebase"))

      allow(UpdatePullRequest).to receive(:new).and_return(dummy_pr_updater)
      allow(dummy_pr_updater).to receive(:run).and_raise(ActiveStorage::FileNotFoundError)

      job.perform_now
    end
  end

  context "the pull is rejected due to a branch protection error on commit signatures" do
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { github_url + "repositories/123" }
    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    before do
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_return("token")

      stub_request(:get, repo_url + "/pulls/1").
        to_return(status: 200, body: github_pull_request, headers: json_header)

      allow(Dependabot::Logger).to receive(:error)
      allow(dummy_pr_updater).
        to receive(:run).and_raise(UpdatePullRequest::BranchProtectionInvalidSignatureError, "foo")
    end

    it "does not raise an error" do
      expect { job.perform_now }.not_to raise_error
    end

    it "does not retry" do
      expect { job.perform_now }.not_to enqueue_job
    end

    it "logs the failure" do
      job.perform_now

      expect(Dependabot::Logger).
        to have_received(:error).
        with(a_hash_including(
               msg: "Unable to update Pull Request ##{pull_request.github_number}.",
               "code.namespace": "UpdatePullRequestJob",
               "exception.type": UpdatePullRequest::BranchProtectionInvalidSignatureError,
               "exception.message": "foo",
               "gh.dependabot_api.pull_request.id": pull_request.id,
               "gh.repo.id": pull_request.update_job.repo.github_id,
               "gh.dependabot_api.update_job.id": pull_request.most_recent_update_job.id,
               "gh.dependabot_api.update_config.id": pull_request.update_job.update_config.id,
               "gh.owner.id": pull_request.update_job.update_config.account.github_id,
             ))
    end

    it "instruments the failure" do
      expect(MetricsClient).
        to receive(:count).
        with("update_pull_request.error", 1,
             tags: hash_including(grouped_update: false, trigger: "rebase"))

      job.perform_now
    end
  end

  context "when unauthorized to update a PR" do
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { github_url + "repositories/123" }
    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end

    before do
      allow(GitHubHelpers).
        to receive(:installation_access_token_for).
        and_return("token")

      stub_request(:get, repo_url + "/pulls/1").
        to_return(status: 200, body: github_pull_request, headers: json_header)

      allow(Dependabot::Logger).to receive(:error)
      allow(dummy_pr_updater).
        to receive(:run).and_raise(Octokit::Unauthorized)
    end

    it "does not raise an error" do
      expect { job.perform_now }.not_to raise_error
    end

    it "retries the job" do
      expect { job.perform_now }.to enqueue_job(described_class)
    end

    context "when retries are exhausted" do
      it "enqueues a job to resynchronise the repository state" do
        expect(SynchronizeRepoStateJob).
          to receive(:perform_later).with(repo: repo, event_source: "job.update_pull_request")

        perform_enqueued_jobs { job.perform_now }
      end

      it "instruments the failure" do
        expect(MetricsClient).
          to receive(:count).
          with("update_pull_request.error", 1,
               tags: hash_including(grouped_update: false, trigger: "rebase"))

        perform_enqueued_jobs(only: described_class) { job.perform_now }
      end
    end
  end
end
