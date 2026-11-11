# frozen_string_literal: true

require "rails_helper"
require "chatops/controller/rspec"

RSpec.describe ChatopsController, :cloud do
  include_context "chatops controller"

  context "ignore conditions" do
    it "explains when a repo doesn't exist" do
      FactoryBot.create(:account, github_login: "rails")
      chat "dependabot ignore_conditions rails/rails", "user", "#dependabot-ops"

      expect(chatop_error).to include("Repository `rails/rails` not found")
    end

    it "includes the repo name lists the ignore conditions for an NWO" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 0)

      chat "dependabot ignore_conditions #{account_name}/#{repo_name}", "user", "#dependabot-ops"

      expect(chatop_response).to include("Repository: #{account_name}/#{repo_name} - GitHub ID: ")
    end

    it "summarizes ignore conditions" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 2)

      chat "dependabot ignore_conditions #{account_name}/#{repo_name}", "user", "#dependabot-ops"

      IgnoreCondition.all.find_each do |ignore_condition|
        expect(chatop_response).to match(
          /
            \|\s*#{ignore_condition.id}\s*
            \|\s*#{ignore_condition.dependency_name}\s*
            \|\s*#{ignore_condition.version_requirement}\s*
            \|\s*#{ignore_condition.update_types}\s*
            \|\s*(config\ file|issue\ comment\ \(#{ignore_condition.issue_comment_id}\))\s*
          /x
        )
      end
    end

    it "supports removal of ignore conditions via the --remove flag" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 1)
      ignore_condition_to_remove = IgnoreCondition.first

      chat "dependabot ignore_conditions #{account_name}/#{repo_name} --remove #{ignore_condition_to_remove.id}",
           "user", "#dependabot-ops"

      expect(chatop_response).
        to match("Removed ignore condition #{ignore_condition_to_remove.id} for #{account_name}/#{repo_name}")
    end

    it "prevents removal of ignore conditions that don't belong to the repo" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 1)
      other_config = FactoryBot.create(:update_config)
      other_repos_ignore_condition = FactoryBot.create(:ignore_condition, update_config: other_config)

      chat "dependabot ignore_conditions #{account_name}/#{repo_name} --remove #{other_repos_ignore_condition.id}",
           "user", "#dependabot-ops"

      expect(chatop_error).
        to match("Ignore condition #{other_repos_ignore_condition.id} does not belong to #{account_name}/#{repo_name}")
    end

    it "only displays update configs which are active" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 1)

      active_update_config = UpdateConfig.first
      inactive_update_config = FactoryBot.create(:update_config, :deleted, repo: Repo.first, package_manager: "pip")

      chat "dependabot ignore_conditions #{account_name}/#{repo_name}", "user", "#dependabot-ops"

      expect(chatop_response).to include("Update Config: #{active_update_config.id}")
      expect(chatop_response).not_to include("Update Config: #{inactive_update_config.id}")
    end

    it "displays update configs using the directories key" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 1)

      active_update_config = UpdateConfig.first
      active_update_config.update!(directory: nil, directories: ["/backend", "/frontend"])

      chat "dependabot ignore_conditions #{account_name}/#{repo_name}", "user", "#dependabot-ops"

      expect(chatop_response).to include("directories: #{active_update_config.directories}")
    end

    it "only displays update configs which have ignore conditions" do
      account_name = "dependabot"
      repo_name = "dependabot-core"
      create_repo_with_ignore_conditions(account_name: account_name, repo_name: repo_name, count: 1)

      config_with_ignore_conditions = UpdateConfig.first
      lonely_update_config = FactoryBot.create(:update_config, :active, repo: Repo.first, package_manager: "pip")

      chat "dependabot ignore_conditions #{account_name}/#{repo_name}", "user", "#dependabot-ops"

      expect(chatop_response).to include("Update Config: #{config_with_ignore_conditions.id}")
      expect(chatop_response).not_to include("Update Config: #{lonely_update_config.id}")
    end
  end

  def create_repo_with_ignore_conditions(account_name:, repo_name:, count: 1)
    account = FactoryBot.create(:account, github_login: account_name)
    repo = FactoryBot.create(:repo, account: account, name: repo_name)
    update_config = FactoryBot.create(:update_config, :active, repo: repo)

    count.times do |n|
      FactoryBot.create(:ignore_condition, update_config: update_config, version_requirement: "#{n}.0")
    end
  end
end
