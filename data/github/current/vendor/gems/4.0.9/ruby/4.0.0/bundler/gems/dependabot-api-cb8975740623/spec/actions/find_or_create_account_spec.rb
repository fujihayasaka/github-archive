# frozen_string_literal: true

require "rails_helper"

RSpec.describe FindOrCreateAccount do
  subject(:action) do
    described_class.new(github_account: github_account)
  end

  let(:github_account) do
    {
      "id": 1144873,
      "login": "greysteil",
      "tenant_id": 42,
      "tenant_slug": "sluggish",
      "type": "User",
    }.with_indifferent_access
  end

  context "given a new account" do
    it "creates the account" do
      expect { action.run }.to change(Account, :count).by(1)
    end

    it "returns the account" do
      expect(action.run).to be_a(Account)
    end
  end

  context "given an account that already exists" do
    let!(:account) do
      FactoryBot.create(
        :account, :active, :user,
        github_id: github_account.fetch("id"),
      )
    end

    it "doesn't create any new accounts" do
      expect { action.run }.not_to change(Account, :count)
    end

    it "returns the account" do
      expect(action.run).to be_a(Account)
    end

    context "and is for a different account type" do
      let!(:account) do
        FactoryBot.create(
          :account, :inactive, :org,
          github_id: github_account.fetch("id"),
        )
      end

      it "creates a new account" do
        expect { action.run }.to change(Account, :count).by(1)
      end
    end
  end

  context "when the github_account includes a login with a shortcode" do
    it "creates the account without the shortcode for Proxima", :proxima do
      github_account["login"] = "greysteil_github"

      expect { action.run }.to change(Account, :count).by(1)

      expect(Account.last.github_login).to eq("greysteil")
    end

    it "creates the account and the tenant shortcode is set for Proxima", :proxima do
      github_account["login"] = "greysteil_github"

      expect { action.run }.to change(Account, :count).by(1)
      expect(Account.last.shortcode).to eq("github")
    end

    it "creates the account _with_ the shortcode outside of Proxima", :cloud, :enterprise do
      github_account["login"] = "greysteil_github"

      expect { action.run }.to change(Account, :count).by(1)

      expect(Account.last.github_login).to eq("greysteil_github")
    end
  end

  context "when the github_account does not include a login with a shortcode" do
    it "creates the account without the shortcode for Proxima", :proxima do
      github_account["login"] = "greysteil"

      expect { action.run }.to change(Account, :count).by(1)

      expect(Account.last.github_login).to eq("greysteil")
      expect(Account.last.shortcode).to be nil
    end
  end
end
