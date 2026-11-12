# frozen_string_literal: true

class AddLevelToBlocklistedTerms < ActiveRecord::Migration[7.0]
  def change
    add_column :blocklisted_terms, :level, :string, null: false, default: "warn"
  end
end
