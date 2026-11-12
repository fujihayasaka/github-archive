# frozen_string_literal: true

require "rails_helper"

RSpec.describe HydroHandlers::GitHub::User do
  describe "setup_account" do
    let(:user) do
      described_class.new(
        {
          id: 1144873,
          login: "greysteil",
          type: "Organization",
          tenant_id: "1234",
          tenant_slug: "hitgub",
        },
        installation_id: 123,
      )
    end

    describe "using a non-global app installation" do
      before do
        allow(GitHubHelpers).
          to receive(:onboard_account_with_global_app?).
          with(github_id: user.id).
          and_return(false)
      end

      it "creates an account" do
        expect(Account.count).to eq(0)

        user.setup_account

        expect(Account.count).to eq(1)
        account = Account.first
        expect(account.github_id).to eq(1144873)
        expect(account.github_login).to eq("greysteil")
        expect(account.current_installation_id).to eq(123)
      end
    end

    describe "using a global app installation" do
      let(:json_header) { { "Content-Type" => "application/json" } }
      let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
      let(:user_url) { github_url + "user/#{user.id}" }
      let(:github_user_body) { fixture("github_responses/user.json") }

      before do
        allow(GitHubHelpers).
          to receive(:onboard_account_with_global_app?).
          with(github_id: user.id).
          and_return(true)
        allow(GitHubHelpers).to receive(:global_access_token_for)
        stub_request(:get, user_url).and_return(body: github_user_body, headers: json_header)
      end

      it "creates an account using the global app" do
        expect(Account.count).to eq(0)

        user.setup_account

        expect(Account.count).to eq(1)
        account = Account.first
        expect(account.github_id).to eq(1144873)
        expect(account.github_login).to eq("greysteil")
        expect(account.current_installation_id).to eq(Account::GLOBAL_APP_INSTALLATION_ID)
      end
    end
  end
end
