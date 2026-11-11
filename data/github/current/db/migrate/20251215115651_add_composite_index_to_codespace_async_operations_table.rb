# typed: true

class AddCompositeIndexToCodespaceAsyncOperationsTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)
  def change
    change_table :codespace_async_operations, bulk: true do |t|
      t.index [:op_ended_at, :operation, :op_started_at], comment: "https://github.com/github/codespaces/issues/22664"
    end
  end
end
