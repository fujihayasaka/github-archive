# typed: true
# frozen_string_literal: true

class CreateEventActionRepositoryOperations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)
  def change
    create_table :event_action_repository_operations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.string :operation, limit: 64, null: false
      t.string :operation_value, limit: 64, null: true

      t.timestamps

      t.index [:repository_id, :operation, :operation_value], name: "index_event_action_repository_operation"
    end
  end
end
