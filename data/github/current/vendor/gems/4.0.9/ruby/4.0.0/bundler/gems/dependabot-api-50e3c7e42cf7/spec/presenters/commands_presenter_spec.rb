# frozen_string_literal: true

require "rails_helper"

RSpec.describe CommandsPresenter do
  subject(:presenter) { described_class.new }

  let(:update_job) { FactoryBot.create(:update_job, update_config: update_config) }
  let(:update_config) { FactoryBot.create(:update_config, repo: repo) }
  let(:repo) { FactoryBot.create(:repo, :public) }

  context "for an individual dependency update" do
    subject(:dependabot_commands_text) { described_class.dependabot_commands_text(update_job, grouped_update: false) }

    it "includes the commands to recreate a PR" do
      expect(dependabot_commands_text).to start_with("You can trigger Dependabot actions by commenting on this PR:")
      expect(dependabot_commands_text).to include("- `@dependabot rebase` will rebase this PR")
      expect(dependabot_commands_text).
        to include("- `@dependabot recreate` will recreate this PR, overwriting any edits")
    end

    it "includes the commands to ignore a PR" do
      expect(dependabot_commands_text).to include("- `@dependabot ignore this major version` will close this PR and ")
      expect(dependabot_commands_text).to include("- `@dependabot ignore this minor version` will close this PR and ")
    end

    it "includes the commands to show the ignore conditions" do
      expect(dependabot_commands_text).to include("- `@dependabot show <dependency name> ignore conditions` ")
    end
  end

  context "for a grouped dependency update" do
    subject(:dependabot_commands_text) { described_class.dependabot_commands_text(update_job, grouped_update: true) }

    it "includes the commands to recreate a PR" do
      expect(dependabot_commands_text).to start_with("You can trigger Dependabot actions by commenting on this PR:")
      expect(dependabot_commands_text).to include("- `@dependabot rebase` will rebase this PR")
      expect(dependabot_commands_text).
        to include("- `@dependabot recreate` will recreate this PR, overwriting any edits")
    end

    it "include the commands to ignore a PR" do
      expect(dependabot_commands_text).
        to include("- `@dependabot ignore <dependency name> major version` will close this group update PR ")
      expect(dependabot_commands_text).
        to include("- `@dependabot ignore <dependency name> minor version` will close this group update PR ")
    end

    it "include the commands to unignore a PR" do
      expect(dependabot_commands_text).
        to include("- `@dependabot unignore <dependency name>` will remove all of the ignore conditions ")
      expect(dependabot_commands_text).
        to include("- `@dependabot unignore <dependency name> <ignore condition>` will remove the ignore condition ")
    end

    it "includes the commands to show the ignore conditions" do
      expect(dependabot_commands_text).to include("- `@dependabot show <dependency name> ignore conditions` ")
    end
  end
end
