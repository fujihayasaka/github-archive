# typed: true
# frozen_string_literal: true

class AddOwnerIdAndRepoIdToMemexAgentTasks < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_agent_tasks, bulk: true do |t|
      t.bigint :owner_id, unsigned: true
      t.bigint :repository_id, unsigned: true
      t.index [:owner_id, :repository_id], name: "index_memex_agent_tasks_on_owner_id_and_repository_id"
    end
  end
end
