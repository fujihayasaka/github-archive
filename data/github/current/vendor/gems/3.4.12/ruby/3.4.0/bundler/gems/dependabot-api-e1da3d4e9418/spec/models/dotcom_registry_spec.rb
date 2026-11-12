# frozen_string_literal: true

require "rails_helper"

RSpec.describe DotcomRegistry do
  describe ".compatible_with?" do
    it "returns true when host and type are compatible with dotcom" do
      valid_credentials =
        credentials(
          {
            "host" => described_class::HOST,
            "type" => described_class::TYPE,
          }
        )

      expect(described_class.compatible_with?(valid_credentials)).to be true
    end

    context "when the give arguments are not compatible with dotcom" do
      it "returns false when host is not dotcom" do
        non_github_credentials =
          credentials(
            {
              "host" => "bitbucket.org",
              "type" => described_class::TYPE,
            }
          )

        expect(described_class.compatible_with?(non_github_credentials)).to be false
      end

      it "returns false when type is not 'git_source'" do
        non_git_source_credentials =
          credentials(
            {
              "host" => described_class::HOST,
              "type" => "rubygems_server",
            }
          )

        expect(described_class.compatible_with?(non_git_source_credentials)).to be false
      end
    end

    def credentials(overrides = {})
      {
        "host" => described_class::HOST,
        "type" => described_class::TYPE,
        "username" => described_class::USERNAME,
        "password" => "",
      }.merge(overrides)
    end
  end

  describe "#credentials" do
    context "when not running in enterprise or Proxima mode" do
      before do
        allow(Dependabot).to receive(:enterprise?).and_return(false)
        allow(Dependabot).to receive(:proxima?).and_return(false)
      end

      it "returns nil" do
        repo = build_stubbed(:repo)
        expect(described_class.new(repo).credentials).to be_nil
      end
    end

    context "when running in enterprise mode" do
      before do
        allow(Dependabot).to receive(:enterprise?).and_return(true)
        allow(Dependabot).to receive(:proxima?).and_return(false)
      end

      it "returns nil when no dotcom access token is available" do
        repo = build_stubbed(:repo)
        stub_request(:post, %r{enterprise/tokens}).
          and_return(status: 404, headers: { "Content-Type" => "application/json" })

        expect(described_class.new(repo).credentials).to be_nil
      end

      context "when generating a dotcom access_token" do
        subject(:registry) { described_class.new(repo) }

        let(:repo) { build_stubbed(:repo) }
        let(:api_url) { File.join(Dependabot::Application.target_github_internal_api_endpoint, "/enterprise/tokens") }
        let(:request_token) { SecureRandom.uuid }
        let(:response_token) { SecureRandom.uuid }

        before do
          allow(GitHubHelpers).to receive(:integration_token).and_return(request_token)
        end

        it "fetches a token via the GHES Connect API" do
          body = { token: response_token }.to_json
          stub_request(:post, api_url).
            with(headers: { "Authorization" => "Bearer #{request_token}" }).
            and_return(status: 201, headers: { "Content-Type" => "application/json" }, body: body)

          result = registry.credentials

          expect(result["host"]).to eq(described_class::HOST)
          expect(result["type"]).to eq(described_class::TYPE)
          expect(result["username"]).to eq(described_class::USERNAME)
          expect(result["password"]).to eq(response_token)
        end

        it "returns nil when a 404 is returned" do
          stub_request(:post, api_url).and_return(status: 404, headers: { "Content-Type" => "application/json" })

          expect(registry.credentials).to be_nil
        end

        it "bubbles up 5XX errors" do
          stub_request(:post, api_url).and_return(status: 500, headers: { "Content-Type" => "application/json" })

          expect { registry.credentials }.to raise_error(Octokit::InternalServerError)
        end
      end
    end

    context "when running in Proxima mode" do
      before do
        allow(Dependabot).to receive(:proxima?).and_return(true)
        allow(Dependabot).to receive(:enterprise?).and_return(false)
        allow(GitHubHelpers).
          to receive(:create_proxima_integration_access_token).
          and_return("a-secret-token")
        stub_request(:get, "#{github_url}user/#{repo.account.github_id}").
          to_return(status: 200,
                    headers: { "Content-Type" => "application/json" },
                    body: { node_id: user_node_id }.to_json)
        stub_request(:get, "#{github_url}repositories/#{repo.github_id}").
          to_return(status: 200,
                    headers: { "Content-Type" => "application/json" },
                    body: { node_id: repo_node_id }.to_json)
      end

      let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
      let(:repo) { build_stubbed(:repo) }
      let(:user_node_id) { "user_node_id" }
      let(:repo_node_id) { "repo_node_id" }

      it "returns nil when proxima app token cannot be retrieved" do
        allow(GitHubHelpers).
          to receive(:create_proxima_integration_access_token).
          and_return(nil)

        expect(described_class.new(repo).credentials).to be_nil
      end

      it "uses the proxima integration provided token" do
        dotcom_credentials = described_class.new(repo).credentials

        expect(dotcom_credentials["password"]).to eq("a-secret-token")
      end
    end
  end
end
