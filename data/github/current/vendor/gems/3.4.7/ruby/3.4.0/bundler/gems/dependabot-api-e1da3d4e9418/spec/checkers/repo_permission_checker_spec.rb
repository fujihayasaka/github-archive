# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepoPermissionChecker do
  subject(:checker) do
    described_class.new(repo: repo, user_github_login: user_github_login)
  end

  let(:repo) do
    FactoryBot.create(
      :repo, :active,
      account: account,
      github_id: 88632334,
    )
  end
  let(:user_github_login) { "greysteil" }

  let(:repo_sync_result) do
    SynchronizeRepoState::SynchronizeRepoStateResult.error(
      reason: SynchronizeRepoState::ACCOUNT_OUT_OF_SYNC
    )
  end
  let(:dummy_repo_sync) { double(run: repo_sync_result) }

  before do
    allow(GitHubHelpers).
      to receive(:installation_access_token_for).
      and_return("secret token")

    allow(SynchronizeRepoState).to receive(:new).
      with(repo: repo, event_source: "action.repo_permission_checker").
      and_return(dummy_repo_sync)
  end

  describe "#permission_level" do
    subject(:permission_level) { checker.permission_level }

    context "with an inactive account" do
      let(:account) { FactoryBot.create(:account, :inactive) }

      it "raises an InaccessibleRepo error" do
        expect(dummy_repo_sync).not_to receive(:run)
        expect { permission_level }.
          to raise_error(described_class::InaccessibleRepo)
      end
    end

    context "with an active account" do
      let(:account) { FactoryBot.create(:account, :active) }

      let(:json_header) { { "Content-Type" => "application/json" } }
      let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
      let(:repo_url) { github_url + "repositories/#{repo.github_id}/" }
      let(:permission_url) do
        repo_url + "collaborators/#{user_github_login}/permission"
      end
      let(:installation_repos_url) do
        github_url + "installation/repositories?per_page=100"
      end

      before do
        stub_request(:get, permission_url).
          to_return(
            status: 200,
            body: fixture("github_responses/repo_permissions_admin.json"),
            headers: json_header,
          )
      end

      it { is_expected.to eq("admin") }

      it "uses tenant headers in Proxima", :proxima do
        permission_level

        expect(WebMock).to have_requested(:get, permission_url).
          with(headers: { "X-GitHub-Tenant" => repo.account.tenant.slug })
      end

      context "when GitHub 401s" do
        before do
          stub_request(:get, permission_url).
            to_return(
              status: 401,
              body: { error: "Bad credentials" }.to_json,
              headers: json_header,
            )
        end

        it "raises Octokit::Unauthorized" do
          expect { permission_level }.to raise_error(Octokit::Unauthorized)
        end

        context "but is fine when retried" do
          before do
            stub_request(:get, permission_url).
              to_return(
                status: 401,
                body: { error: "Bad credentials" }.to_json,
                headers: json_header,
              ).then.
              to_return(
                status: 200,
                body: fixture("github_responses/repo_permissions_admin.json"),
                headers: json_header,
              )
          end

          it { is_expected.to eq("admin") }
        end
      end

      context "when GitHub 403s" do
        before do
          stub_request(:get, permission_url).
            to_return(
              status: 403,
              body: fixture("github_responses/forbidden_unavailable_to_integration.json"),
              headers: json_header,
            )
        end

        context "because Dependabot is no longer installed on the account" do
          before do
            installation_url = "#{github_url}users/"\
                               "#{repo.account.github_login}/installation"
            stub_request(:get, installation_url).to_return(status: 404)
          end

          it "raises an InaccessibleRepo error" do
            expect(dummy_repo_sync).to receive(:run)
            expect { permission_level }.
              to raise_error(described_class::InaccessibleRepo)
          end
        end

        context "because Dependabot no longer has access to the repo" do
          let(:installation_id) { repo.account.current_installation_id.to_s }
          let(:github_repos) do
            fixture("github_responses/installation_repos.json").
              gsub("88632334", "88")
          end
          let(:github_installation) do
            fixture("github_responses/installation.json").
              gsub("25222", installation_id)
          end

          before do
            installation_url = "#{github_url}users/"\
                               "#{repo.account.github_login}/installation"
            stub_request(:get, installation_url).
              to_return(
                status: 200,
                body: github_installation,
                headers: json_header,
              )
            stub_request(
              :get,
              "#{github_url}app/installations/#{installation_id}",
            ).to_return(status: 200, body: "{}", headers: json_header)
            stub_request(:get, installation_repos_url).
              to_return(status: 200, body: github_repos, headers: json_header)
          end

          it "raises an InaccessibleRepo error" do
            expect(dummy_repo_sync).to receive(:run)
            expect { permission_level }.
              to raise_error(described_class::InaccessibleRepo)
          end
        end
      end
    end
  end
end
