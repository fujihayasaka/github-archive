# frozen_string_literal: true

require "rails_helper"

RSpec.describe HydroHandlers::GitHub::User do
  describe "setup_account" do
    let(:user) do
      described_class.new(
        {
          id: 90210,
          login: "monalisa",
          type: "Organization",
          tenant_id: "1234",
          tenant_slug: "hitgub",
        },
        installation_id: 123,
      )
    end

    it "creates an account" do
      expect(Account.count).to eq(0)

      user.setup_account

      expect(Account.count).to eq(1)
      account = Account.first
      expect(account.github_id).to eq(90210)
      expect(account.github_login).to eq("monalisa")
      expect(account.current_installation_id).to eq(123)
    end
  end
end
