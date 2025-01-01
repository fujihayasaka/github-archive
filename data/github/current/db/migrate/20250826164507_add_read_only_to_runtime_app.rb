# typed: true
# frozen_string_literal: true

class AddReadOnlyToRuntimeApp < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table(:runtime_apps, bulk: true) do |t|
      t.column :read_only_kv, :boolean, null: false, default: false, comment: "If the data store is read-only"
    end
  end
end
