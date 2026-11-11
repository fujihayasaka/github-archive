# typed: true

class DropCopilotBlockedRemoteRepositories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    drop_table :copilot_blocked_remote_repositories, if_exists: true
  end
end
