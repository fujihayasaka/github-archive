# frozen_string_literal: true

class AddPublicationIndexingColumns < ActiveRecord::Migration[5.2]
  def change
    add_column :references, :index, :integer, null: false
    remove_index :references, :advisory_id
    add_index :references, [:advisory_id, :index]

    add_column :vulnerabilities, :withdrawn_at, :datetime
    add_column :vulnerabilities, :index, :integer, null: false
    remove_index :vulnerabilities, :advisory_id
    add_index :vulnerabilities, [:advisory_id, :index]
  end
end
