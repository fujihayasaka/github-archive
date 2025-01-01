# frozen_string_literal: true

class AddSkippedCountToImports < ActiveRecord::Migration[5.2]
  def change
    add_column :imports, :skipped_count, :integer, default: 0, null: false
  end
end
