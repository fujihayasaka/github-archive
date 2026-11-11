# typed: true

class AddIndexToCodespaceAsyncOperationsTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)
  def change
    change_table :codespace_async_operations, bulk: true do |t|
      t.index [:codespace_id, :operation, :op_ended_at], comment: "https://github.com/github/mysql-database-usage/issues/2617"
    end
  end
end
