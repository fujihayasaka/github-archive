# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include ActiveSupport::Testing::TimeHelpers

  include_context "chatops controller"

  describe "room requirements" do
    before do
      FactoryBot.create(
        :account,
        github_login: "github"
      )
    end

    it "permits calls from the #dependabot-ops room" do
      chat "dependabot info github", "user", "#dependabot-ops"

      expect(chatop_response).not_to include(
        "must be run in #dependabot-ops"
      )
    end

    it "permits calls from the #dependabot-chatops room" do
      chat "dependabot info github", "user", "#dependabot-chatops"

      expect(chatop_response).not_to include(
        "must be run in #dependabot-chatops"
      )
    end

    it "permits calls from the dev shell" do
      chat "dependabot info github", "user", "ssh"

      expect(chatop_response).not_to include(
        "must be run in #dependabot-ops"
      )
    end

    it "disallows calls with no context" do
      chat "dependabot info github", "user"

      expect(chatop_response).to include(
        "must be run in one of these rooms"
      )
    end

    it "disallows calls from a different slack room" do
      chat "dependabot info github", "user", "#danger-room"

      expect(chatop_response).to include(
        "must be run in one of these rooms"
      )
    end
  end

  describe "find_by_nwo!" do
    let(:tenant) { nil }

    it "finds the active repo" do
      account = FactoryBot.create(:account, github_login: "dependabot")
      repo = FactoryBot.create(:repo, account: account, name: "dependabot-core")
      FactoryBot.create(:update_config, :active, repo: repo)

      # this repo is inactive, so we should not find it
      FactoryBot.create(:repo, account: account, name: "dependabot-core")

      expect(described_class.new.find_by_nwo!("dependabot/dependabot-core", tenant)).to eq(repo)
    end

    it "raises an error if there are more than one active repo" do
      account = FactoryBot.create(:account, github_login: "dependabot")
      repo1 = FactoryBot.create(:repo, account: account, name: "dependabot-core")
      FactoryBot.create(:update_config, :active, repo: repo1)

      repo2 = FactoryBot.create(:repo, account: account, name: "dependabot-core")
      FactoryBot.create(:update_config, :active, repo: repo2)

      expect { described_class.new.find_by_nwo!("dependabot/dependabot-core", tenant) }.
        to raise_error("`dependabot` has more than one active repo with that name: #{repo1.id}, #{repo2.id}")
    end

    it "returns an inactive repo if there are no active repos" do
      account = FactoryBot.create(:account, github_login: "dependabot")
      # a repo is inactive when it has no active update configs
      repo = FactoryBot.create(:repo, account: account, name: "dependabot-core")

      expect(described_class.new.find_by_nwo!("dependabot/dependabot-core", tenant)).to eq(repo)
    end
  end

  private

  def permitted_slack_room
    "#dependabot-ops"
  end
end
