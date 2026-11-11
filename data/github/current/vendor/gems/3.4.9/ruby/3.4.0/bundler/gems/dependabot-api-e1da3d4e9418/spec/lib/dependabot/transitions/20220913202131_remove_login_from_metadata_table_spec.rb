# frozen_string_literal: true

require "rails_helper"

require_relative "../../../../lib/dependabot/transitions/20220913202131_remove_login_from_metadata_table.rb"
RSpec.describe "RemoveLoginFromMetadataTable" do
  let(:transition) do
    Dependabot::Transitions::RemoveLoginFromMetadataTable.new(dry_run: false)
  end

  let(:dry_run_transition) do
    Dependabot::Transitions::RemoveLoginFromMetadataTable.new
  end

  context "write" do
    it "performs the transition" do
      account = FactoryBot.create(:account)
      account_transition = AccountTransition.create(
        account: account,
        installation_id: 0,
        metadata: {
          initiator_github_id: 1,
          initiator_github_login: "monalisa",
        },
        sort_key: 0,
        to_state: :active,
      )

      expect(account_transition.metadata).to include({ "initiator_github_login" => "monalisa" })

      transition.perform

      expect(account_transition.reload.metadata).not_to include("initiator_github_login")
    end
  end

  context "dry run" do
    it "does nothing on a dry run" do
      account = FactoryBot.create(:account)
      account_transition = AccountTransition.create(
        account: account,
        installation_id: 0,
        metadata: {
          initiator_github_id: 1,
          initiator_github_login: "monalisa",
        },
        sort_key: 0,
        to_state: :active,
      )

      expect(account_transition.metadata).to include({ "initiator_github_login" => "monalisa" })

      dry_run_transition.perform

      expect(account_transition.reload.metadata).to include({ "initiator_github_login" => "monalisa" })
    end
  end
end
