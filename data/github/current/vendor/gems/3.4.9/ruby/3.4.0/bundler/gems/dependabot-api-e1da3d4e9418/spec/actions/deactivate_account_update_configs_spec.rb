# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeactivateAccountUpdateConfigs do
  subject(:action) { described_class.new(account: account, user: user) }

  let(:user) { { "id": 123, "login": "dependabot" } }
  let(:repo) { FactoryBot.create(:repo) }
  let(:account) { repo.account }

  let!(:update_config) do
    FactoryBot.create(:update_config, :active, repo: repo)
  end

  context "when the account is active" do
    it "leaves the update config alone" do
      expect { action.run }.
        not_to change { update_config.current_state(force_reload: true) }
    end
  end

  context "when the account is inactive" do
    before do
      account.transition_to!(
        :inactive,
        installation_id: account.current_installation_id,
      )
    end

    it "marks the update config as deleted" do
      expect { action.run }.
        to change { update_config.current_state(force_reload: true) }.
        from("active").to("deleted")
    end

    context "when update config belongs to a different account" do
      let!(:update_config) do
        FactoryBot.create(:update_config, :active)
      end

      it "leaves the update config alone" do
        expect { action.run }.
          not_to change { update_config.current_state(force_reload: true) }
      end
    end

    context "when update config is pending" do
      let!(:update_config) do
        FactoryBot.create(:update_config, :pending)
      end

      it "leaves the update config alone" do
        expect { action.run }.
          not_to change { update_config.current_state(force_reload: true) }
      end
    end
  end
end
