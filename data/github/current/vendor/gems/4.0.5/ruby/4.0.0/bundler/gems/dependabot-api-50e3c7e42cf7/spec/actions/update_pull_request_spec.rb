# frozen_string_literal: true

require "rails_helper"

RSpec.describe UpdatePullRequest do
  subject(:action) do
    described_class.new(
      pull_request: pull_request,
      updated_dependency_files: updated_dependency_files,
      new_base_commit_sha: new_base_commit_sha,
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/88632334" }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }
  let(:pr_head_branch) { JSON.parse(pr_body).dig("head", "ref") }
  let(:commits_body) { fixture("github_responses/commits_edited.json") }
  let(:updated_pr_body) do
    fixture("github_responses/pull_request_updated.json")
  end
  let(:updated_ref_body) { fixture("github_responses/ref.json") }
  let(:new_base_commit_sha) { "sha" }

  let(:repo) { FactoryBot.create(:repo, github_id: 88632334) }
  let(:update_config) { FactoryBot.create(:update_config, :active, repo: repo) }
  let(:pull_request) do
    FactoryBot.create(
      :pull_request, :updating,
      repo: repo,
      update_config: update_config,
      head_commit_sha: "1e2d2afe8320998baecdfe127a49dca9a6650e07",
      dependabot_commit_sha: "1e2d2afe8320998baecdfe127a49dca9a6650e07",
      github_number: 18,
    )
  end
  let(:updated_dependency_files) do
    [
      Dependabot::DependencyFile.new(name: "Gemfile", content: "codes"),
      Dependabot::DependencyFile.new(name: "Gemfile.lock", content: "locks"),
    ]
  end

  let(:updated_reference) do
    stub_request(:get, github_url + "repositories/1/git/refs/1").
      to_return(status: 200, body: updated_ref_body, headers: json_header)
    Octokit::Client.new(access_token: "junk", api_endpoint: github_url).ref(1, 1)
  end

  let(:dummy_pull_request_updater) do
    instance_double(
      Dependabot::PullRequestUpdater,
      update: updated_reference,
    )
  end

  let(:original_description) do
    "Original description\n\n"\
    "[//]: # (dependabot-automerge-start)\n"\
    "[//]: # (dependabot-automerge-end)\n\n"\
    "---n<details>\n"\
    "<summary>Dependabot commands and options</summary>\n"\
    "</details>"
  end

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, repo_url + "/pulls/18").
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:patch, repo_url + "/pulls/18").
      with(body: { body: original_description }.to_json).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
    allow(Dependabot::PullRequestUpdater).
      to receive(:new).
      and_return(dummy_pull_request_updater)
  end

  shared_examples "attempts to update the PR" do
    it "attempts to update the PR" do
      expect(dummy_pull_request_updater).to receive(:update)
      action.run
    end
  end

  shared_examples "does not attempt to update the PR" do
    it "does not attempt to update the PR" do
      expect(dummy_pull_request_updater).not_to receive(:update)
      action.run
    end
  end

  it "locks PR updates using Restraints.for_branch_changes" do
    # reassign to local var to avoid clashing variable names
    expected_repo = repo
    expect(Restraints).to receive(:for_branch_changes) do |repo:, branch_name:, &block|
      expect(repo).to eq(expected_repo)
      expect(branch_name).to eq(pr_head_branch)
      expect(block).not_to be_nil
    end

    action.run
  end

  context "when an error occurs while updating the PR for a human" do
    let(:pr_comments_url) { repo_url + "/issues/18/comments" }

    before do
      stub_request(:post, pr_comments_url)
    end

    it "adds a comment explaining that there was an error" do
      allow(dummy_pull_request_updater).to receive(:update).and_return(nil)
      pull_request.most_recent_update_job.update(trigger_type: "manual_rebase")

      action.run

      expect(WebMock).
        to have_requested(:post, pr_comments_url).
        with(
          body: { body: Comments::Rebase::SOMETHING_WENT_WRONG }.to_json,
        )
    end
  end

  context "when the head commit sha is not the same as the dependabot one" do
    before { pull_request.update!(dependabot_commit_sha: "outdated") }

    let(:pr_comments_url) { repo_url + "/issues/18/comments" }

    before do
      stub_request(:get, repo_url + "/pulls/18/commits").
        to_return(status: 200, body: commits_body, headers: json_header)
      stub_request(:post, pr_comments_url)
    end

    include_examples "does not attempt to update the PR"

    it "does not update the PR in the database" do
      expect { action.run }.
        to not_change { pull_request.head_commit_sha }.
        and not_change { pull_request.dependabot_commit_sha }
    end

    it "updates the GitHub PR to remove any updating warning" do
      action.run

      expect(WebMock).
        to have_requested(:patch, repo_url + "/pulls/18").
        with(body: { body: original_description }.to_json)
    end

    it "marks the PR as up-to-date" do
      expect { action.run }.
        to change { pull_request.reload.current_state }.
        from("updating").to("up_to_date")
    end

    context "when the PR has been edited by someone other than Dependabot" do
      it "adds a comment explaining why the PR was not updated" do
        pull_request.most_recent_update_job.update(trigger_type: "manual_rebase")
        action.run

        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(
            body: { body: Comments::Rebase::PULL_REQUEST_EDITED }.to_json,
          )
      end
    end

    context "when learning about the new commit for the first time" do
      before { pull_request.update!(head_commit_sha: "outdated") }

      it "updates the PR in the database" do
        expect { action.run }.
          to change(pull_request, :head_commit_sha).
          and not_change { pull_request.dependabot_commit_sha }
      end
    end

    context "when asked to overwrite edits" do
      before do
        pull_request.last_transition.
          update!(metadata: { "overwrite_edits" => true })
      end

      include_examples "attempts to update the PR"

      it "updates the PR in the database" do
        expect { action.run }.
          to change(pull_request, :head_commit_sha).
          and change(pull_request, :dependabot_commit_sha)
      end
    end

    context "for an edited PR with dependabot skipped commits" do
      let(:commits_body) do
        fixture("github_responses/commits_edited_skipped.json")
      end

      include_examples "attempts to update the PR"
    end

    context "for a PR which has been edited by someone other than Dependabot" do
      before do
        stub_request(:post, pr_comments_url)
        pull_request.most_recent_update_job.update(trigger_type: "manual_rebase")
      end

      let(:commits_body) { fixture("github_responses/commits_edited.json") }
      let(:pr_comments_url) { repo_url + "/issues/#{pull_request.github_number}/comments" }

      it "adds a comment to the PR" do
        action.run

        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(
            body: { body: Comments::Rebase::PULL_REQUEST_EDITED }.to_json,
          )
      end
    end
  end

  context "when the base commit sha hasn't changed" do
    before { pull_request.update!(base_commit_sha: new_base_commit_sha) }

    context "and the PR is mergeable" do
      include_examples "does not attempt to update the PR"

      it "doesn't update the PR in the database" do
        expect { action.run }.not_to change(pull_request, :head_commit_sha)
      end

      it "updates the GitHub PR to remove any updating warning" do
        action.run

        expect(WebMock).
          to have_requested(:patch, repo_url + "/pulls/18").
          with(body: { body: original_description }.to_json)
      end

      it "marks the PR as up-to-date" do
        expect { action.run }.
          to change { pull_request.reload.current_state }.
          from("updating").to("up_to_date")
      end
    end

    context "when the update was requested by a human" do
      let(:pr_comments_url) { repo_url + "/issues/18/comments" }

      before do
        stub_request(:post, pr_comments_url)
      end

      it "adds a comment explaining why the PR has not changed" do
        pull_request.most_recent_update_job.update(trigger_type: "manual_rebase")
        action.run

        expect(WebMock).
          to have_requested(:post, pr_comments_url).
          with(
            body: { body: Comments::Rebase::BASE_COMMIT_UNCHANGED }.to_json,
          )
      end
    end

    context "and the PR is mergeable but we are asked to overwrite edits" do
      before do
        pull_request.last_transition.
          update!(metadata: { "overwrite_edits" => true })
      end

      let(:updated_reference) do
        stub_request(:get, github_url + "repositories/1/git/refs/1").
          to_return(status: 200, body: updated_ref_body, headers: json_header)
        Octokit::Client.new(access_token: "junk", api_endpoint: github_url).ref(1, 1)
      end

      let(:dummy_pull_request_updater) do
        instance_double(
          Dependabot::PullRequestUpdater,
          update: updated_reference,
        )
      end

      before do
        allow(Dependabot::PullRequestUpdater).
          to receive(:new).
          and_return(dummy_pull_request_updater)
      end

      include_examples "attempts to update the PR"

      it "updates the pull request in the database" do
        expect { action.run }.
          to change(pull_request, :dependabot_commit_sha).
          to(updated_reference.object.sha).
          and change(pull_request, :head_commit_sha).
          to(updated_reference.object.sha)
      end

      it "marks the PR as up-to-date" do
        expect { action.run }.
          to change { pull_request.reload.current_state }.
          from("updating").to("up_to_date")
      end
    end

    context "and the PR is not mergeable" do
      before { pr_body.gsub!('"mergeable": true', '"mergeable": false') }

      let(:updated_reference) do
        stub_request(:get, github_url + "repositories/1/git/refs/1").
          to_return(status: 200, body: updated_ref_body, headers: json_header)
        Octokit::Client.new(access_token: "junk", api_endpoint: github_url).ref(1, 1)
      end

      let(:dummy_pull_request_updater) do
        instance_double(
          Dependabot::PullRequestUpdater,
          update: updated_reference,
        )
      end

      before do
        allow(Dependabot::PullRequestUpdater).
          to receive(:new).
          and_return(dummy_pull_request_updater)
      end

      include_examples "attempts to update the PR"

      it "updates the pull request in the database" do
        expect { action.run }.
          to change(pull_request, :dependabot_commit_sha).
          to(updated_reference.object.sha).
          and change(pull_request, :head_commit_sha).
          to(updated_reference.object.sha)
      end

      it "marks the PR as up-to-date" do
        expect { action.run }.
          to change { pull_request.reload.current_state }.
          from("updating").to("up_to_date")
      end
    end
  end

  context "when the installation no longer has access to the Repository's pull requests" do
    let(:installation_id) { repo.account.current_installation_id.to_s }
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos.json").gsub("88632334", "88")
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id)
    end

    before do
      stub_request(:patch, repo_url + "/pulls/18").
        with(body: { body: original_description }.to_json).
        to_return(
          status: 403,
          body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
          headers: json_header,
        )
      stub_request(:get, %r{#{github_url}app/installations/\d+}).
        to_return(status: 200, body: "{}", headers: json_header)
      github_id = repo.account.github_id
      stub_request(:get, "#{github_url}user/#{github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, repo_url).to_return(status: 404)

      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_return(OpenStruct.new(dependabot_config_file_enabled: true))
    end

    it "leaves the update_config" do
      expect { action.run }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when the repository has been archived" do
    let(:installation_id) { repo.account.current_installation_id.to_s }
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos.json").gsub("88632334", "88")
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id)
    end
    let(:archived_github_repo) do
      fixture("github_responses/repo.json").
        gsub('"archived": false', '"archived": true').
        gsub("\"id\": 27347476", "\"id\": #{repo.account.github_id}")
    end

    before do
      stub_request(:patch, repo_url + "/pulls/18").
        with(body: { body: original_description }.to_json).
        to_return(
          status: 403,
          body: fixture("github_responses/forbidden_archived.json"),
          headers: json_header,
        )
      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_return(OpenStruct.new(dependabot_config_file_enabled: true))
      stub_request(:get, %r{#{github_url}app/installations/\d+}).
        to_return(status: 200, body: "{}", headers: json_header)
      github_id = repo.account.github_id
      stub_request(:get, "#{github_url}user/#{github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, repo_url).
        to_return(status: 200, body: archived_github_repo, headers: json_header)
    end

    it "deactivates the repository" do
      expect { action.run }.
        to change { update_config.reload.current_state }.from("active").to("deleted")
    end
  end

  context "when the repo is deleted mid-update (very rare)" do
    let(:installation_id) { repo.account.current_installation_id.to_s }
    let(:installation_repos_url) do
      github_url + "installation/repositories?per_page=100"
    end
    let(:github_repos) do
      fixture("github_responses/installation_repos.json").gsub("88632334", "88")
    end
    let(:github_installation) do
      fixture("github_responses/installation.json").
        gsub("25222", installation_id)
    end

    before do
      stub_request(:patch, repo_url + "/pulls/18").
        with(body: { body: original_description }.to_json).
        to_return(status: 404)
      github_id = repo.account.github_id
      stub_request(:get, "#{github_url}user/#{github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, repo_url).to_return(status: 404)

      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)
    end

    it "leaves the update_config" do
      expect { action.run }.
        not_to change { update_config.reload.current_state }
    end
  end

  context "when the branch being updated is protected" do
    let(:pr_comments_url) do
      repo_url + "/issues/#{pull_request.github_number}/comments"
    end
    let(:github_comment) { fixture("github_responses/issue_comment.json") }
    let(:github_comments) do
      fixture("github_responses/issue_comments_not_mentioned.json")
    end

    before do
      allow(dummy_pull_request_updater).to receive(:update).
        and_raise(Dependabot::PullRequestUpdater::BranchProtected)
      stub_request(:get, pr_comments_url).
        to_return(status: 200, body: github_comments, headers: json_header)
      stub_request(:post, pr_comments_url).
        to_return(status: 200, body: github_comment, headers: json_header)
    end

    include_examples "attempts to update the PR"

    it "doesn't update the PR in the database" do
      expect { action.run }.not_to change(pull_request, :head_commit_sha)
    end

    it "updates the GitHub PR to remove any updating warning" do
      action.run

      expect(WebMock).
        to have_requested(:patch, repo_url + "/pulls/18").
        with(body: { body: original_description }.to_json)
    end

    it "marks the PR as up-to-date" do
      expect { action.run }.
        to change { pull_request.reload.current_state }.
        from("updating").to("up_to_date")
    end

    it "creates a comment" do
      action.run

      expect(WebMock).
        to have_requested(:post, pr_comments_url).
        with(
          body: {
            body: "Dependabot attempted to update this pull request, but "\
                  "because the branch `bump_webmock_to_3.0.1` is protected it "\
                  "was unable to do so.",
          }.to_json,
        )
    end

    context "and a comment already exists" do
      let(:github_comments) do
        fixture("github_responses/issue_comments_protected_branch.json")
      end

      it "does not create a comment" do
        action.run

        expect(WebMock).not_to have_requested(:post, pr_comments_url)
      end
    end
  end

  context "when the branch being updated is protected on signed commits" do
    let(:error) do
      Octokit::Error.
        from_response({
                        status: 422,
                        body: fixture("github_responses/pull_requests/unprocessable_branch_protection_signature.json"),
                      })
    end

    let(:pr_comments_url) do
      repo_url + "/issues/#{pull_request.github_number}/comments"
    end

    before do
      allow(dummy_pull_request_updater).
        to receive(:update).
        and_raise(error)
    end

    it "raises a specific error" do
      expect { action.run }.to raise_error(described_class::BranchProtectionInvalidSignatureError)
    end

    it "doesn't update the PR in the database" do
      expect do
        action.run
      rescue described_class::BranchProtectionInvalidSignatureError
        nil
      end.not_to change(pull_request, :head_commit_sha)
    end

    it "does not create a comment" do
      begin
        action.run
      rescue described_class::BranchProtectionInvalidSignatureError
        nil
      end

      expect(WebMock).not_to have_requested(:post, pr_comments_url)
    end
  end

  context "when a invalid git submodule causes the update to fail" do
    let(:error_response) do
      {
        method: :POST,
        status: 422,
        url: repo_url + "/git/trees",
        body: "GitRPC::BadGitmodules",
      }
    end

    before do
      allow(dummy_pull_request_updater).
        to receive(:update).
        and_raise(Octokit::UnprocessableEntity, error_response)
    end

    it "notifies the user about the issue" do
      expect { action.run }.
        to have_enqueued_job(NotifyGitHubOfFailureJob).
        with(
          update_job: pull_request.update_job,
          error_hash: {
            "error-type" => "bad_gitmodules",
            "error-detail" => nil,
          },
        )
    end
  end

  context "when Dependabot updates the PR" do
    include_examples "attempts to update the PR"

    it "updates the pull request in the database" do
      expect { action.run }.
        to change(pull_request, :dependabot_commit_sha).
        to(updated_reference.object.sha).
        and change(pull_request, :head_commit_sha).
        to(updated_reference.object.sha)
    end

    it "updates the pull request's CI status" do
      expect { action.run }.
        to have_enqueued_job(UpdatePullRequestCiStatusJob).
        with(
          pull_request: pull_request,
          refs_to_check: [updated_reference.object.sha, new_base_commit_sha],
        )
    end

    it "marks the PR as up-to-date" do
      expect { action.run }.
        to change { pull_request.reload.current_state }.
        from("updating").to("up_to_date")
    end

    context "but the GitHub update fails (e.g., if the branch was deleted)" do
      let(:updated_reference) { nil }

      it "updates the GitHub PR to remove any updating warning" do
        action.run

        expect(WebMock).
          to have_requested(:patch, repo_url + "/pulls/18").
          with(body: { body: original_description }.to_json)
      end
    end

    context "if the PR has a merge request" do
      before { pull_request.update!(merge_requested: true) }

      it "enqueues a job to merge the PR" do
        expect { action.run }.
          to have_enqueued_job(MergePullRequestJob).
          with(pull_request: pull_request)
      end
    end

    context "if the PR doesn't have a merge request" do
      before { pull_request.update!(merge_requested: false) }

      it "does not enqueue a job to merge the PR" do
        expect { action.run }.not_to have_enqueued_job(MergePullRequestJob)
      end
    end

    context "for a pull request in state `merged`" do
      before { pull_request.transition_to!(:merged) }

      it "doesn't update the PR's state" do
        expect { action.run }.
          not_to change { pull_request.reload.current_state }
      end
    end

    context "when the pull request doesn't have a warning in the description" do
      before do
        stub_request(:get, repo_url + "/pulls/18").
          to_return(status: 200, body: pr_body, headers: json_header)
      end

      it "doesn't blow up" do
        action.run

        expect(WebMock).
          to have_requested(:patch, repo_url + "/pulls/18").
          with(body: { body: original_description }.to_json)
      end
    end
  end
end
