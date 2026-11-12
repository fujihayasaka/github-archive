# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivateAccount do
  include ActiveSupport::Testing::TimeHelpers

  subject(:action) do
    described_class.new(
      account: account,
      installation_id: install_fixture["installation"]["id"],
      sender: install_fixture["sender"],
    )
  end

  let(:install_fixture) do
    json_fixture("github_webhooks/installation_created")
  end

  describe "given an inactive account" do
    let!(:account) do
      FactoryBot.create(
        :account, :inactive, :user,
        github_id: install_fixture.dig("installation", "account", "id"),
      )
    end

    it "activates the account" do
      expect { action.run }.
        to change { account.reload.current_state }.
        from("inactive").to("active")
    end

    it "stores details of the user who linked the account" do
      account = action.run
      expect(account.last_transition.metadata["initiator_github_id"]).
        to eq(1144873)
    end
  end

  describe "given an active account" do
    let!(:account) do
      FactoryBot.create(
        :account, :active, :user,
        github_id: install_fixture.dig("installation", "account", "id"),
        installation_id: installation_id,
      )
    end

    context "which is active using the current installation ID" do
      let(:installation_id) { install_fixture["installation"]["id"] }

      it "returns the already activate account" do
        result = action.run
        expect(result).to eq(account)
        expect(result.current_state).to eq("active")
      end

      it "doesn't create any account transitions" do
        expect { action.run }.not_to change(AccountTransition, :count)
      end
    end

    context "attached to an outdated installation ID" do
      let(:installation_id) { "outdated_id" }

      before do
        header = { "Content-Type" => "application/json" }
        github_url = Dependabot::Application.target_github_internal_api_endpoint

        stub_request(:get, github_url + "app/installations/21399").
          to_return(status: 200, body: "{}", headers: header)
      end

      it "returns the activated account" do
        result = action.run
        expect(result).to eq(account)
        expect(result.current_state).to eq("active")
      end

      it "transitions the account twice" do
        expect { action.run }.to change(AccountTransition, :count).by(2)
      end
    end

    context "using to an outdated installation ID" do
      let(:installation_id) { "outdated_id" }

      before do
        header = { "Content-Type" => "application/json" }
        github_url = Dependabot::Application.target_github_internal_api_endpoint

        stub_request(:get, github_url + "app/installations/21399").
          to_return(status: 404, body: "{}", headers: header)
      end

      it "raises an error" do
        expect { action.run }.
          to raise_error(ActivateAccount::InstallationNotFound)
      end
    end

    context "for the same installation ID (i.e., a race)" do
      let(:installation_id) { install_fixture["installation"]["id"] }

      before do
        allow_any_instance_of(Account).to receive(:in_state?).
          and_return(true, false)
        allow(AccountTransition).to receive(:exists?).
          and_return(true, false)
      end

      it "returns the already activated account" do
        expect(Account.in_state(:active).count).to eq(1)
        returned_account = action.run
        expect(returned_account.current_state).to eq("active")
        expect(Account.in_state(:active).count).to eq(1)
      end
    end
  end
end
