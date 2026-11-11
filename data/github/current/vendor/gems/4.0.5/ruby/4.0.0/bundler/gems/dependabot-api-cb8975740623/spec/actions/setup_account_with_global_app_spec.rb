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

  context "when a concurrent process activates the account with a real installation_id" do
    let!(:account) do
      FactoryBot.create(
        :account, :inactive,
        account_type: "org",
        installation_id: Account::GLOBAL_APP_INSTALLATION_ID,
        github_id: github_account_id,
      )
    end

    before do
      # Simulate a race condition: after the guard check sees the account as
      # inactive, a concurrent process (e.g., InstallationCreateHandler)
      # activates the account with a real installation_id.
      allow(FindOrCreateAccount).to receive(:new).and_wrap_original do |original, **args|
        account.transition_to!(:active, installation_id: 9999)
        original.call(**args)
      end

      # ActivateAccount sees the account is already active with installation_id 9999,
      # which differs from GLOBAL_APP_INSTALLATION_ID (0). It then checks whether
      # installation 0 is still valid by calling the GitHub API. Stub it to return 404
      # so ActivateAccount raises InstallationNotFound, which the new rescue handles.
      stub_request(:get, "#{github_url}app/installations/#{Account::GLOBAL_APP_INSTALLATION_ID}").
        to_return(status: 404, body: "{}", headers: json_header)
    end

    it "returns the active account without raising" do
      result = action.run
      expect(result).to eq(account)
      expect(result.active?).to be true
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

  context "when running in Proxima mode", :proxima do
    let(:tenant_id) { "1234" }
    let(:tenant_slug) { "lugman-inc" }

    it "passes the tenant header when fetching account details" do
      stub = stub_request(:get, "#{github_url}user/#{github_account_id}").
             with(headers: { "X-GitHub-Tenant" => tenant_slug }).
             to_return(
               status: 200,
               body: fixture("github_responses/user_by_id.json").gsub("30846345", github_account_id.to_s),
               headers: json_header,
             )

      account = action.run
      expect(stub).to have_been_requested
      expect(account.github_id).to eq(github_account_id)
      expect(account.tenant.github_id).to eq(1234)
      expect(account.tenant.slug).to eq("lugman-inc")
    end

    context "when tenant_slug is missing" do
      let(:tenant_slug) { nil }

      it "raises an ArgumentError" do
        expect { action.run }.to raise_error(ArgumentError, "tenant_slug must be present in Proxima mode")
      end
    end

    context "when tenant_slug is blank" do
      let(:tenant_slug) { "" }

      it "raises an ArgumentError" do
        expect { action.run }.to raise_error(ArgumentError, "tenant_slug must be present in Proxima mode")
      end
    end
  end

  context "when not running in Proxima mode", proxima: false do
    it "does not pass the tenant header when fetching account details" do
      # Verify the request is made without the X-GitHub-Tenant header
      stub = stub_request(:get, "#{github_url}user/#{github_account_id}").
             with { |request| request.headers["X-GitHub-Tenant"].nil? }.
             to_return(
               status: 200,
               body: fixture("github_responses/user_by_id.json").gsub("30846345", github_account_id.to_s),
               headers: json_header,
             )

      action.run
      expect(stub).to have_been_requested
    end
  end
end
