# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletePullRequestBranch do
  subject(:action) { described_class.new(pull_request: pull_request) }

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:repo_url) { github_url + "repositories/88632334" }
  let(:branch_url) { repo_url + "/git/refs/heads/bump_webmock_to_3.0.1" }
  let(:pr_url) { repo_url + "/pulls/18" }
  let(:updated_pr_body) do
    fixture("github_responses/pull_request_updated.json")
  end

  let(:account) { FactoryBot.create(:account, :active, github_login: "a-user") }
  let(:repo) { FactoryBot.create(:repo, github_id: 88632334, account: account) }
  let!(:update_config) do
    FactoryBot.create(:update_config, :active, repo: repo)
  end
  let(:pull_request) do
    FactoryBot.create(:pull_request, status, repo: repo, github_number: 18)
  end
  let(:status) { :updating }
  let(:pr_body) { fixture("github_responses/pull_request_updating.json") }

  before do
    allow(GitHubHelpers).to receive(:installation_access_token_for)
    stub_request(:get, pr_url).
      to_return(status: 200, body: pr_body, headers: json_header)
    stub_request(:delete, branch_url).
      to_return(status: 200, body: updated_pr_body, headers: json_header)
  end

  context "when the pull request is updating" do
    let(:status) { :updating }
    let(:pr_body) { fixture("github_responses/pull_request_updating.json") }

    it "no-ops" do
      action.run
      expect(WebMock).not_to have_requested(:delete, branch_url)
    end
  end

  context "when the account has been disabled" do
    let(:account) { FactoryBot.create(:account, :inactive) }

    it "no-ops" do
      action.run
      expect(WebMock).not_to have_requested(:get, pr_url)
      expect(WebMock).not_to have_requested(:delete, branch_url)
    end
  end

  context "when the repo has been deleted" do
    let(:installation_id) { account.current_installation_id.to_s }
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
      stub_request(:get, pr_url).to_return(status: 404)
      allow(Dependabot::Application.dependabot_repository_settings_client).
        to receive(:get_repository_settings).
        and_raise(GitHub::Twirp::DependabotRepositorySettings::NotFound)
      stub_request(:get, "#{github_url}user/#{account.github_id}/installation").
        to_return(status: 200, body: github_installation, headers: json_header)
      stub_request(:get, installation_repos_url).
        to_return(status: 200, body: github_repos, headers: json_header)
      stub_request(:get, repo_url).to_return(status: 404)
      stub_request(
        :get,
        "#{github_url}app/installations/#{installation_id}",
      ).to_return(status: 200, body: "{}", headers: json_header)
    end

    it "does not delete the update config" do
      expect { action.run }.
        not_to change { update_config.current_state(force_reload: true) }
      expect(WebMock).not_to have_requested(:delete, branch_url)
    end
  end

  context "when the pull request is merged" do
    let(:status) { :merged }
    let(:pr_body) { fixture("github_responses/pull_request_merged.json") }

    context "and there are other open PRs depending on it" do
      let(:open_prs_url) { "#{repo_url}/pulls?head=a-user:bump_webmock_to_3.0.1&state=open" }

      before do
        stub_request(:get, open_prs_url).
          to_return(status: 200, body: "[{}]", headers: json_header)
      end

      it "does not delete the branch" do
        action.run
        expect(WebMock).not_to have_requested(:delete, branch_url)
      end

      it "includes a tenant header when requesting open PRs", :proxima do
        action.run

        expect(WebMock).to have_requested(:get, open_prs_url).
          with(headers: { "X-GitHub-Tenant" => repo.account.tenant.slug })
      end
    end

    context "and there are no other open PRs depending on it" do
      before do
        url = "#{repo_url}/pulls?head=a-user:bump_webmock_to_3.0.1&state=open"
        stub_request(:get, url).
          to_return(status: 200, body: "[]", headers: json_header)
      end

      it "deletes the branch" do
        action.run
        expect(WebMock).to have_requested(:delete, branch_url)
      end

      context "when there is a race" do
        before do
          stub_request(:delete, branch_url).
            to_return(
              status: 422,
              body: { message: "Reference does not exist" }.to_json,
              headers: json_header,
            )
        end

        it "quietly ignores it" do
          expect { action.run }.not_to raise_error
          expect(WebMock).to have_requested(:delete, branch_url)
        end
      end
    end
  end

  context "when branch protection is enabled" do
    let(:status) { :merged }
    let(:pr_body) { fixture("github_responses/pull_request_merged.json") }
    let(:api_error) { "protected branch" }

    before do
      url = "#{repo_url}/pulls?head=a-user:bump_webmock_to_3.0.1&state=open"
      stub_request(:get, url).
        to_return(status: 200, body: "[]", headers: json_header)

      stub_request(:delete, branch_url).
        to_return(
          status: 422,
          body: { message: api_error }.to_json,
          headers: json_header,
        )
    end

    it "quietly ignores it" do
      expect { action.run }.not_to raise_error
      expect(WebMock).to have_requested(:delete, branch_url)
    end

    context "with authorized push actors" do
      let(:api_error) do
        "You're not authorized to push to this branch. "\
        "Visit https://help.github.com/articles/about-"\
        "protected-branches/ for more information."
      end

      it "quietly ignores it" do
        expect { action.run }.not_to raise_error
        expect(WebMock).to have_requested(:delete, branch_url)
      end
    end
  end

  context "when repository rules prevent deleting the branch" do
    let(:status) { :merged }
    let(:pr_body) { fixture("github_responses/pull_request_merged.json") }
    let(:api_error) { "Cannot delete this branch" }

    before do
      url = "#{repo_url}/pulls?head=a-user:bump_webmock_to_3.0.1&state=open"
      stub_request(:get, url).
        to_return(status: 200, body: "[]", headers: json_header)

      stub_request(:delete, branch_url).
        to_return(
          status: 422,
          body: { message: api_error }.to_json,
          headers: json_header,
        )
    end

    it "quietly ignores it" do
      expect { action.run }.not_to raise_error
      expect(WebMock).to have_requested(:delete, branch_url)
    end
  end
end
