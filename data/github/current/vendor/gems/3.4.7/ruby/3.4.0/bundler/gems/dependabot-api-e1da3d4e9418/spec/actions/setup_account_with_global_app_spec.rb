# frozen_string_literal: true

require "rails_helper"

RSpec.describe SetupAccountWithGlobalApp do
  subject(:action) do
    described_class.new(
      github_id: github_account_id,
      tenant_id: tenant_id,
      tenant_slug: tenant_slug,
      event_source: "test"
    )
  end

  let(:github_account_id) { 12345 }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:github_url) { Dependabot::Application.target_github_internal_api_endpoint }
  let(:global_access_token_url) { "#{github_url}app/global/access_tokens" }
  let(:tenant_id) { Dependabot.proxima? ? "1234" : nil }
  let(:tenant_slug) { Dependabot.proxima? ? "lugman-inc" : nil }

  before do
    # We cache access tokens, so let's make sure we clear them out between tests
    Rails.cache.clear
    stub_request(:post, global_access_token_url).
      with(body: { target_id: github_account_id }.to_json).
      to_return(
        status: 200,
        body: erb_fixture("github_responses/global_access_token.json"),
        headers: json_header,
      )
    stub_request(:get, "#{github_url}user/#{github_account_id}").
      to_return(
        status: 200,
        body: fixture("github_responses/user_by_id.json").gsub("30846345", github_account_id.to_s),
        headers: json_header,
      )
  end

  context "when the account hasn't been setup yet" do
    it "creates the account" do
      expect { action.run }.to change(Account, :count).by(1)
    end

    it "populates the account with the right details" do
      account = action.run
      expect(account.github_id).to eq(github_account_id)
      expect(account.current_installation_id).to eq(Account::GLOBAL_APP_INSTALLATION_ID)
      expect(account.active?).to be true
      expect(account.github_login).to eq("dsp-testing")
      expect(account.tenant.github_id).to eq(1234) if Dependabot.proxima?
      expect(account.tenant.slug).to eq("lugman-inc") if Dependabot.proxima?
    end
  end

  context "when the account has already been setup and is active" do
    before do
      FactoryBot.create(
        :account, :active,
        account_type: "org",
        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
        github_id: github_account_id,
      )
    end

    it "doesn't create the account" do
      expect { action.run }.not_to change(Account, :count)
    end
  end

  context "when the account has already been setup and is inactive" do
    before do
      FactoryBot.create(
        :account, :inactive,
        account_type: "org",
        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
        github_id: github_account_id,
      )
    end

    it "doesn't create the account" do
      expect { action.run }.not_to change(Account, :count)
    end

    it "activates the account" do
      account = action.run
      expect(account.active?).to be true
    end
  end

  context "when the account is not found" do
    before do
      stub_request(:post, global_access_token_url).
        with(body: { target_id: github_account_id }.to_json).
        to_return(
          status: 404,
          body: fixture("github_responses/not_found.json"),
          headers: json_header,
        )
    end

    it "raises AccountNotFound" do
      expect { action.run }.to raise_error(SetupAccountWithGlobalApp::AccountNotFound)
    end
  end

  context "when the account is unprocessable" do
    before do
      stub_request(:post, global_access_token_url).
        with(body: { target_id: github_account_id }.to_json).
        to_return(
          status: 422,
          body: { message: "Unprocessable Entity" }.to_json,
          headers: json_header,
        )
    end

    it "raises AccountNotAccessible" do
      expect { action.run }.to raise_error(SetupAccountWithGlobalApp::AccountNotAccessible)
    end
  end
end
