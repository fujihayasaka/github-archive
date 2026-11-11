# frozen_string_literal: true

require "rails_helper"

RSpec.describe GitHub::RESTClient::AccountAuthentication do
  describe "#using_account_auth" do
    let(:bad_credentials_error) { fixture("github_responses/graphql_bad_credentials.json") }
    let(:json_header) { { "Content-Type" => "application/json" } }
    let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
    let(:user_url) { github_url + "user" }
    let(:user_response) { fixture("github_responses/user.json") }

    let(:account) { create(:account, :active, :user) }
    let(:client) { GitHub::RESTClient.new.using_account_auth(account: account) }

    let(:install_access_token) do
      erb_fixture("github_responses/installation_access_token.json")
    end

    before do
      GitHubHelpers.delete_cached_access_token_for(account:)

      # Return a generated token using the pattern "<github id>.<counter>".
      # The github id allows tests to validate which account the tokens come from
      # and the counter gives uniqueness to each token.
      i = 0
      stub_request(:post, %r{app/global/access_tokens}).to_return do |r|
        i += 1
        body = JSON.parse(r.body)
        target_id = body["target_id"]
        {
          status: 200,
          body: JSON.parse(install_access_token).merge("token" => "#{target_id}.#{i}").to_json,
          headers: json_header,
        }
      end
    end

    it "is not included in clients that do not call using_account_authentication" do
      expect(GitHub::RESTClient.new.middleware.handlers).
        not_to include(Dependabot::OctokitMiddleware::AccessTokenAuthentication)
    end

    it "adds a new access token authentication middleware" do
      index = client.middleware.handlers.index(Dependabot::OctokitMiddleware::AccessTokenAuthentication)
      expect(index).not_to be_nil
      middleware = client.middleware.handlers[index].build

      # validate the middleware's access token
      access_token = middleware.instance_variable_get(:@token)
      expect(access_token).not_to be_nil
      expect(access_token.start_with?(account.github_id.to_s)).to be(true)

      stub_request(:get, user_url).
        to_return(status: 200, body: user_response, headers: json_header)
      client.user
      expect(WebMock).to(have_requested(:get, user_url).with do |r|
        expect(r.headers["Authorization"]).to eq("token #{access_token}")
      end)
    end

    it "regenerates the account access token when receiving a bad credentials error" do
      stub_request(:get, user_url).
        to_return(status: 401, body: bad_credentials_error, headers: json_header)

      expect { client.user }.to raise_error(Octokit::Unauthorized)

      tokens = []
      expect(WebMock).to(have_requested(:get, user_url).times(2).with do |r|
        tokens << r.headers["Authorization"]
      end)

      expect(tokens.uniq.length).to eq(2)
    end

    context "when the account has a tenant" do
      let(:tenant) { create(:tenant, slug: "microsoft", shortcode: "abc") }
      let(:account) { create(:account, :active, :user, tenant:) }

      it "inserts a tenant header when the tenant is present", :proxima do
        stub_request(:get, user_url).
          to_return(status: 200, body: user_response, headers: json_header)
        client.user
        expect(WebMock).to(have_requested(:get, user_url).with do |r|
          # subtle: note the little h due to header normalization
          expect(r.headers["X-Github-Tenant"]).to eq("microsoft")
        end)
      end

      it "does not send the tenant header on dotcom", :cloud do
        stub_request(:get, user_url).
          to_return(status: 200, body: user_response, headers: json_header)
        client.user
        expect(WebMock).to(have_requested(:get, user_url).with do |r|
          # subtle: note the little h due to header normalization
          expect(r.headers["X-Github-Tenant"]).to be_nil
        end)
      end
    end

    describe "with existing access token authentication middleware" do
      let(:new_account) { create(:account, :active, :user) }

      before do
        GitHubHelpers.delete_cached_access_token_for(account: new_account)
      end

      it "updates the existing middleware" do
        client.using_account_auth(account: new_account)

        index = client.middleware.handlers.index(Dependabot::OctokitMiddleware::AccessTokenAuthentication)
        expect(index).not_to be_nil
        middleware = client.middleware.handlers[index].build

        access_token = middleware.instance_variable_get(:@token)
        expect(access_token).not_to be_nil
        expect(access_token.start_with?(new_account.github_id.to_s)).to be(true)
      end
    end
  end
end
