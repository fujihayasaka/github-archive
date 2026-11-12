# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequestCiStatus do
  subject(:action) do
    described_class.new(pull_request: pull_request, refs_to_check:)
  end

  let(:refs_to_check) { %w(basecommitsha headcommitsha dependabotcommitsha) }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { "#{github_url}repositories/88632334" }

  let(:account) { FactoryBot.create(:account, :active, installation_id: 9876) }
  let(:repo) { FactoryBot.create(:repo, :bump_test, account: account) }
  let(:pull_request) do
    create(
      :pull_request, :bump_test,
      head_commit_sha: "headcommitsha",
      dependabot_commit_sha: "dependabotcommitsha",
      repo: repo,
    )
  end
  let(:redis) { Dependabot.redis }
  let(:prs_client) { instance_double(GitHub::Twirp::DependabotPullRequests) }

  before do
    redis.flushdb

    allow(GitHub::Twirp::DependabotPullRequests).to receive(:new).and_return(prs_client)
    allow(prs_client).to receive(:get_ci_status).and_return(
      {
        pull_request.head_commit_sha =>
          action.resolve_ci_status_symbol(MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_PENDING),
        pull_request.base_commit_sha =>
          action.resolve_ci_status_symbol(MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_SUCCESS),
        pull_request.dependabot_commit_sha =>
          action.resolve_ci_status_symbol(MonolithTwirp::Dependabot::PullRequests::V1::CiStatus::CI_STATUS_FAILURE),
      }
    )
  end

  it "updates the pull request's head commit CI status" do
    expect { action.run }.
      to change { pull_request.reload.head_commit_ci_status }.
      from(nil).to(GitHub::CheckRun::Status::PENDING)
  end

  it "updates the pull request's base commit CI status" do
    expect { action.run }.
      to change { pull_request.reload.base_commit_ci_status }.
      from(nil).to(GitHub::CheckRun::Conclusion::SUCCESS)
  end

  it "updates the pull request's dependabot commit CI status" do
    expect { action.run }.
      to change { pull_request.reload.dependabot_commit_ci_status }.
      from(nil).to(GitHub::CheckRun::Conclusion::FAILURE)
  end

  context "when refs_to_check does not include a PR ref" do
    let(:refs_to_check) { %w(basecommitsha headcommitsha) }

    it "does not update the excluded ref" do
      expect { action.run }.
        not_to change { pull_request.reload.dependabot_commit_ci_status }
    end
  end

  context "with a pending PR" do
    let(:pull_request) do
      pr = create(
        :pull_request,
        github_number: PullRequest::PENDING_PR_NUMBER,
        head_commit_sha: PullRequest::PENDING_COMMIT_SHA,
        dependabot_commit_sha: PullRequest::PENDING_COMMIT_SHA,
        repo: repo,
      )
      pr.transition_to(:pending)
      pr
    end

    it "does not update the PR" do
      action.run
      expect(pull_request.reload.head_commit_ci_status).to be_nil
    end
  end

  context "with a repo that thought it had no CI" do
    before { repo.update!(has_ci: false) }

    it "updates the repo's CI status" do
      expect(repo.has_ci?).to eq(false)

      action.run

      expect(repo.reload.has_ci?).to eq(true)
    end
  end

  context "when GitHub 404s" do
    before do
      allow(GitHubHelpers).to receive(:access_token_for)
      allow(prs_client).to receive(:get_ci_status).
        and_raise(
          GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
            "test",
            MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
              type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_REPO_NOT_FOUND,
              message: "error"
            )
          )
        )

      stub_request(:get, repo_url).
        to_return(status: 404, headers: json_header)
      github_id = account.github_id
      stub_request(:get, "#{github_url}user/#{github_id}/installation").
        to_return(status: 404)

      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)
    end

    it "updates the account" do
      expect { action.run }.
        to change { account.reload.current_state }.
        from("active").to("inactive")
    end
  end

  context "when access to the repository is blocked" do
    let(:repo_sync_result) do
      SynchronizeRepoState::SynchronizeRepoStateResult.error(
        reason: SynchronizeRepoState::MISSING_INSTALLATION
      )
    end
    let(:dummy_repo_sync) { double(run: repo_sync_result) }
    let(:github_status_data) do
      fixture("github_responses/combined_status_empty.json")
    end

    before do
      allow(GitHubHelpers).to receive(:access_token_for)
      allow(prs_client).to receive(:get_ci_status).
        and_raise(GitHub::Twirp::DependabotPullRequests::ServiceError.for_error(
                    "test",
                    MonolithTwirp::Dependabot::PullRequests::V1::Error.new(
                      type: MonolithTwirp::Dependabot::PullRequests::V1::ErrorType::ERROR_TYPE_DEPENDABOT_CANNOT_WRITE,
                      message: "error"
                    )
                  ))

      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)
      stub_request(:get, repo_url).
        to_return(
          status: 403,
          body: fixture("github_responses/access_blocked.json"),
          headers: json_header,
        )
      allow(SynchronizeAccountState).
        to receive(:new).
        and_return(dummy_repo_sync)
    end

    it "doesn't raise" do
      expect(dummy_repo_sync).to receive(:run)
      expect { action.run }.not_to raise_error
    end
  end
end
