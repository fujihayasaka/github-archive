# frozen_string_literal: true

class AddBulkToImports < ActiveRecord::Migration[6.1]
  def change
    add_column :imports, :bulk, :boolean, null: false, default: false
  end
end
