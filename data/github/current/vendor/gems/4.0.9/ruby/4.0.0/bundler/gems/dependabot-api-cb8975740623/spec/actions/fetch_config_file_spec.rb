# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchConfigFile do
  subject(:action) do
    described_class.new(
      account: account,
      repo_name: repo_name,
      repo_github_id: repo_github_id,
    )
  end

  let(:repo_name) { "dependabot-test" }
  let(:repo_github_id) { 88632334 }

  context "for an account that isn't active" do
    let(:account) { FactoryBot.create(:account, :dependabot, :inactive) }

    it "returns nil" do
      expect(action.run).to be_nil
    end
  end

  context "for an account that is active" do
    let(:account) { FactoryBot.create(:account, :dependabot, :active) }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:repo_url) { "#{github_url}repositories/#{repo_github_id}" }
    let(:contents_url) { repo_url + "/contents/.github/dependabot.yml" }
    let(:json_header) { { "Content-Type" => "application/json" } }

    before do
      allow(GitHubHelpers).
        to receive(:access_token_for).
        and_return("token")
    end

    context "for a private fork (we can't fetch files for these)" do
      let(:repo_name) { "dependabot-test-ghsa-cj79-j376-j6hc" }

      before do
        stub_request(:get, contents_url).
          to_return(
            status: 403,
            body: fixture("github_responses/forbidden_unspecified.json"),
            headers: json_header,
          )
      end

      it "returns nil" do
        expect(action.run).to be_nil
      end
    end

    context "when access to the repository is blocked" do
      before do
        stub_request(:get, contents_url).
          to_return(
            status: 403,
            body: fixture("github_responses/access_blocked.json"),
            headers: json_header,
          )
      end

      it "raises an error" do
        expect { action.run }.to raise_error(Octokit::RepositoryUnavailable)
      end
    end

    context "when the .github/dependabot.yml can be fetched" do
      before do
        stub_request(:get, contents_url).
          to_return(
            status: 200,
            body: fixture("github_responses/contents_config_file.json"),
            headers: json_header,
          )
      end

      it "returns the contents of the config file" do
        config_file = action.run
        expect(config_file.content).to eq("Config file contents")
        expect(config_file.path).to eq(".github/dependabot.yml")
      end
    end

    context "when the .github/dependabot.yml can't be fetched" do
      before do
        stub_request(:get, contents_url).
          to_return(
            status: 404,
            body: fixture("github_responses/not_found.json"),
            headers: json_header,
          )
      end

      context "and neither can .github or .github/dependabot.yaml" do
        before do
          stub_request(:get, repo_url + "/contents/.github").
            to_return(
              status: 404,
              body: fixture("github_responses/not_found.json"),
              headers: json_header,
            )
          stub_request(:get, repo_url + "/contents/.github/dependabot.yaml").
            to_return(
              status: 404,
              body: fixture("github_responses/not_found.json"),
              headers: json_header,
            )
        end

        it "returns nil" do
          expect(action.run).to be_nil
        end
      end

      context "and .github is a directory" do
        before do
          stub_request(:get, repo_url + "/contents/.github").
            to_return(
              status: 200,
              body: fixture("github_responses/repo_content.json"),
              headers: json_header,
            )
          stub_request(:get, repo_url + "/contents/.github/dependabot.yaml").
            to_return(
              status: 404,
              body: fixture("github_responses/not_found.json"),
              headers: json_header,
            )
        end

        it "returns nil" do
          expect(action.run).to be_nil
        end

        context "with a dependabot.yaml in it" do
          before do
            stub_request(:get, repo_url + "/contents/.github/dependabot.yaml").
              to_return(
                status: 200,
                body: fixture("github_responses/contents_config_file.json"),
                headers: json_header,
              )
          end

          it "returns the contents of the config file" do
            config_file = action.run
            expect(config_file.content).to eq("Config file contents")
            expect(config_file.path).to eq(".github/dependabot.yaml")
          end
        end
      end

      context "and .github is a submodule" do
        before do
          stub_request(:get, repo_url + "/contents/.github").
            to_return(
              status: 200,
              body: fixture("github_responses/repo_contents_submodule.json"),
              headers: json_header,
            )

          submodule_url =
            "#{github_url}repos/dependabot/dependabot-config/"\
            "contents/dependabot.yml"\
            "?ref=3fc4de72be1d46516160ce5056b38aad329806e2"
          stub_request(:get, submodule_url).
            to_return(
              status: 200,
              body: fixture("github_responses/contents_config_file.json"),
              headers: json_header,
            )
        end

        it "returns the contents of the config file" do
          expect(action.run.content).to eq("Config file contents")
        end
      end
    end

    context "for a specific sha" do
      subject(:action) do
        described_class.new(
          account: account,
          repo_name: repo_name,
          repo_github_id: repo_github_id,
          ref: sha,
        )
      end

      let(:sha) { "ce587453ced02b1526dfb4cb910479d431683101" }

      before do
        stub_request(:get, contents_url + "?ref=#{sha}").
          to_return(
            status: 200,
            body: fixture("github_responses/contents_config_file.json"),
            headers: json_header,
          )
      end

      it "returns the contents of the config file" do
        config_file = action.run
        expect(config_file.content).to eq("Config file contents")
        expect(config_file.path).to eq(".github/dependabot.yml")
      end
    end
  end
end
