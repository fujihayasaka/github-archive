class MakeCodespaceNullableOnAsyncOperation < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)
  def change
    change_column_null :codespace_async_operations, :codespace_id, true
  end
end
