# frozen_string_literal: true

class CreateBlacklistedTerms < ActiveRecord::Migration[5.2]
  def change
    create_table :blacklisted_terms do |t|
      t.string :pattern, null: false
      t.timestamps
    end
  end
end
