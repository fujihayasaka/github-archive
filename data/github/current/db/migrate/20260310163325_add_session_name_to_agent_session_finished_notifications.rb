# typed: true
# frozen_string_literal: true

class AddSessionNameToAgentSessionFinishedNotifications < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Copilot)

  def change
    change_table :agent_session_finished_notifications, bulk: true do |t|
      t.string :session_name, limit: 255, null: true
      t.string :task_name, limit: 255, null: true
    end
  end
end
