# typed: true
# frozen_string_literal: true

class CreateMemexAgentTasks < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    create_table :memex_agent_tasks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :task_uuid, "binary(16)", null: false
      t.timestamps precision: 6, null: false

      t.index [:task_uuid], unique: true, name: "index_memex_agent_tasks_on_task_uuid"
    end
  end
end
