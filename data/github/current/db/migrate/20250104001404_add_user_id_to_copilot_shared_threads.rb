# typed: true

class AddUserIdToCopilotSharedThreads < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::CopilotPLG

  def change
    add_column :copilot_shared_threads, :user_id, :bigint, unsigned: true, null: false
  end
end
