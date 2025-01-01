# frozen_string_literal: true

class AddAdvisoriesCWEs < ActiveRecord::Migration[6.0]
  def change
    create_table :advisories_cwes do |t|
      t.belongs_to :advisory, null: false
      t.belongs_to :cwe, limit: 9, type: :string, null: false
    end

    add_index :advisories_cwes, [:advisory_id, :cwe_id], unique: true
  end
end
