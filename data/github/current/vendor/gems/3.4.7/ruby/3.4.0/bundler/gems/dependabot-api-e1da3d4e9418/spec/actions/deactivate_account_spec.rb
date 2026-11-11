# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeactivateAccount do
  subject(:action) do
    described_class.new(
      account: account,
      installation_id: fixture["installation"]["id"],
      sender: fixture["sender"],
    )
  end

  let(:fixture) do
    json_fixture("github_webhooks/installation_deleted")
  end

  context "given an existing account" do
    context "that is active" do
      let!(:account) do
        FactoryBot.create(
          :account,
          :active,
          github_id: fixture.dig("installation", "account", "id"),
          installation_id: fixture.dig("installation", "id"),
        )
      end
      let(:repo) { FactoryBot.create(:repo, account: account) }
      let!(:update_config) do
        FactoryBot.create(:update_config, :active, repo: repo)
      end

      it "deactivates the account" do
        expect { action.run }.
          to change { account.current_state(force_reload: true) }.
          from("active").to("inactive")
      end

      it "stores details of the user who deactivated the account" do
        action.run
        expect(account.last_transition.metadata["initiator_github_id"]).
          to eq(1)
      end

      it "instruments the deactivation with a default event source" do
        expect(MetricsClient).to receive(:increment).
          with("account_transition.inactive",
               tags: { event_source: "unknown", repos: anything })
        action.run
      end

      it "deactivates active update config" do
        expect { action.run }.
          to change { update_config.current_state(force_reload: true) }.
          from("active").to("deleted")
      end
    end

    context "that is inactive" do
      let!(:account) do
        FactoryBot.create(
          :account,
          :inactive,
          github_id: fixture.dig("installation", "account", "id"),
        )
      end

      it "returns the inactive account" do
        returned_account = action.run
        expect(returned_account.current_state).to eq("inactive")
      end

      context "for the same installation ID (i.e., a race)" do
        let!(:account) do
          account = FactoryBot.create(
            :account,
            :active,
            github_id: fixture.dig("installation", "account", "id"),
            installation_id: fixture.dig("installation", "id"),
          )
          account.transition_to!(
            :inactive,
            installation_id: fixture.dig("installation", "id"),
          )
          account
        end

        it "returns the already deactivated account" do
          expect(Account.in_state(:inactive).count).to eq(1)
          returned_account = action.run
          expect(returned_account.current_state).to eq("inactive")
          expect(Account.in_state(:inactive).count).to eq(1)
        end

        context "with a close race" do
          before do
            allow(AccountTransition).to receive(:exists?).
              and_return(false, true)
          end

          it "returns the already deactivated account" do
            expect(Account.in_state(:inactive).count).to eq(1)
            returned_account = action.run
            expect(returned_account.current_state).to eq("inactive")
            expect(Account.in_state(:inactive).count).to eq(1)
          end
        end
      end

      context "when activated in a race with the same installation id" do
        let!(:account) do
          installation_id = fixture.dig("installation", "id")
          account = FactoryBot.create(
            :account,
            :active,
            github_id: fixture.dig("installation", "account", "id"),
            installation_id: installation_id,
          )
          account.transition_to!(
            :inactive,
            installation_id: installation_id,
          )
          account.transition_to!(
            :active,
            installation_id: installation_id,
          )
          account
        end

        it "deactivates the account" do
          expect(Account.in_state(:inactive).count).to eq(0)
          returned_account = action.run
          expect(returned_account.current_state).to eq("inactive")
          expect(Account.in_state(:inactive).count).to eq(1)
        end
      end
    end
  end
end
