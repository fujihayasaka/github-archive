# frozen_string_literal: true

require "rails_helper"

RSpec.describe HandleRecreateRequestJob, type: :job do
  include ActiveJob::TestHelper

  subject(:job) { described_class.new(pull_request: pr) }

  let(:repo) { FactoryBot.create(:repo, :active, github_id: 123) }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:head_commit_sha) { "1e2d2afe8320998baecdfe127a49dca9a6650e07" }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/123" }
  let(:comments_url) { repo_url + "/issues/#{pr.github_number}/comments" }

  before do
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return("token")

    stub_request(:get, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)
    stub_request(:patch, repo_url + "/pulls/1").
      to_return(status: 200, body: github_pull_request, headers: json_header)

    allow(Rails.logger).to receive(:info)
  end

  shared_examples "updates the pull request" do
    it "marks the PR as updating" do
      expect { job.perform_now }.
        to change { pr.current_state(force_reload: true) }.
        from("up_to_date").to("updating")
      expect(pr.last_transition.metadata["overwrite_edits"]).to eq(true)
    end

    it "queues up a job to update the pull request" do
      expect { job.perform_now }.
        to have_enqueued_job(PrioritizedJobs::StartUpdateJob::Low).
        with do |job|
          expect(job.update_config.repo_id).to eq(pr.repo_id)
          expect(job.package_manager).to eq(pr.update_job.package_manager)
          expect(job.dependencies).to eq(pr.updated_dependencies.map(&:name))
        end
    end

    it "updates the pull request's description" do
      job.perform_now
      expect(WebMock).to have_requested(:patch, repo_url + "/pulls/1")
    end
  end

  shared_examples "does not update the pull request" do
    it "doesn't mark the PR as updating" do
      expect { job.perform_now }.
        not_to change { pr.current_state(force_reload: true) }
    end

    it "does not create a new update job" do
      expect { job.perform_now }.not_to change(UpdateJob, :count)
    end

    it "does not update the pull request's description" do
      job.perform_now
      expect(WebMock).not_to have_requested(:patch, repo_url + "/pulls/1")
    end
  end

  context "for a PR that can't be fetched" do
    before { stub_request(:get, repo_url + "/pulls/1").to_return(status: 404) }

    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end

    let!(:pr) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        github_number: 1,
        head_commit_sha: "not-github",
        dependabot_commit_sha: "not-github",
      )
    end

    before do
      result = SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
      )
      dummy_repo_synchronizer = double(run: result)
      expect(SynchronizeRepoState).
        to receive(:new).with(repo: pr.repo,
                              event_source: "job.handle_recreate_request").
        and_return(dummy_repo_synchronizer)
      expect(dummy_repo_synchronizer).to receive(:run)
    end

    include_examples "does not update the pull request"
  end

  context "for an edited PR" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end
    let!(:pr) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        github_number: 1,
        head_commit_sha: "not-github",
        dependabot_commit_sha: "not-github",
      )
    end
    let(:commits_body) { fixture("github_responses/commits_edited.json") }

    before do
      stub_request(:get, repo_url + "/pulls/1/commits").
        to_return(status: 200, body: commits_body, headers: json_header)
    end

    include_examples "updates the pull request"
  end

  context "for an edited PR with dependabot skipped commits" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end
    let!(:pr) do
      FactoryBot.create(
        :pull_request,
        repo: repo,
        github_number: 1,
        head_commit_sha: "not-github",
        dependabot_commit_sha: "not-github",
      )
    end
    let(:pr_comment) { fixture("github_responses/issue_comment.json") }
    let(:commits_body) do
      fixture("github_responses/commits_edited_skipped.json")
    end

    before do
      stub_request(:get, repo_url + "/pulls/1/commits").
        to_return(status: 200, body: commits_body, headers: json_header)
    end

    before do
      stub_request(:post, comments_url).
        to_return(status: 200, body: pr_comment, headers: json_header)
    end

    include_examples "updates the pull request"
  end

  context "for a PR that is already updating" do
    let(:github_pull_request) do
      fixture("github_responses/pull_request_dirty.json")
    end
    let!(:pr) do
      FactoryBot.create(
        :pull_request, :updating,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
      )
    end

    include_examples "does not update the pull request"

    it "updates the existing update job to be an overwrite edits one" do
      expect { job.perform_now }.
        to change { pr.last_transition.metadata["overwrite_edits"] }.
        from(nil).to(true)
    end
  end

  context "for an unedited PR" do
    let!(:pr) do
      FactoryBot.create(
        :pull_request, pr_state,
        repo: repo,
        github_number: 1,
        head_commit_sha: head_commit_sha,
        dependabot_commit_sha: head_commit_sha,
        base_commit_sha: base_commit_sha,
      )
    end
    let(:pr_state) { :up_to_date }
    let(:base_commit_sha) { "basecommitsha" }

    let(:github_pull_request) do
      fixture("github_responses/pull_request_mergeable.json")
    end
    let(:github_commit) { fixture("github_responses/commit.json") }
    let(:commit_comment) { fixture("github_responses/commit_comment.json") }
    let(:pr_comment) { fixture("github_responses/issue_comment.json") }

    before do
      stub_request(:get, repo_url + "/commits/master").
        to_return(status: 200, body: github_commit, headers: json_header)

      stub_request(
        :post,
        repo_url + "/commits/#{head_commit_sha}/comments",
      ).to_return(status: 200, body: commit_comment, headers: json_header)

      stub_request(:post, comments_url).
        to_return(status: 200, body: pr_comment, headers: json_header)
    end

    context "with new commits" do
      it "does not comment on the old commit" do
        job.perform_now
        expect(WebMock).not_to have_requested(
          :post,
          repo_url + "/commits/#{head_commit_sha}/comments",
        )
      end

      it "does not comment on the GitHub PR" do
        job.perform_now
        expect(WebMock).not_to have_requested(:post, comments_url)
      end

      include_examples "updates the pull request"

      context "when the PR was created against a custom branch" do
        let(:github_pull_request) do
          fixture("github_responses/pull_request_mergeable.json").
            gsub("master", "my_branch")
        end

        before do
          stub_request(:get, repo_url + "/commits/master").
            to_return(status: 404)

          stub_request(:get, repo_url + "/commits/my_branch").
            to_return(status: 200, body: github_commit, headers: json_header)
        end

        include_examples "updates the pull request"
      end
    end

    context "with no new commits" do
      let(:base_commit_sha) { "8c9a9d170dcac59eac7b834da1abe6678b2f7dc9" }

      include_examples "updates the pull request"

      context "and five recreate requests today already" do
        before do
          5.times do
            pr.transition_to(:updating, overwrite_edits: true)
            pr.transition_to(:up_to_date)
          end
        end

        include_examples "does not update the pull request"

        it "posts a comment on the GitHub PR" do
          job.perform_now
          expect(WebMock).
            to have_requested(:post, comments_url).
            with(body: /up-to-date with master/)
        end
      end
    end

    context "with a deleted update_config" do
      before do
        pr.update_config.transition_to!(:deleted)
      end

      it "posts a comment on the GitHub PR" do
        job.perform_now
        expect(WebMock).
          to have_requested(:post, comments_url).
          with(body: /has been deleted/)
      end
    end
  end
end
