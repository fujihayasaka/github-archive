# typed: true

class DropCopilotBlockedGitHubRepositories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    drop_table :copilot_blocked_github_repositories, if_exists: true
  end
end
