# frozen_string_literal: true

class CreatePublishedAdvisoryTables < ActiveRecord::Migration[5.2]
  def up
    remove_index :advisories, :created_at
    remove_index :advisories, :severity
    remove_index :advisories, :updated_at
    remove_index :advisories, :withdrawn_at

    create_table :vulnerabilities do |t|
      t.integer :advisory_id, null: false
      t.string :package_ecosystem
      t.string :package_name
      t.integer :severity
      t.string :vulnerable_version_range
      t.string :first_patched_version
      t.timestamps

      t.index :advisory_id
    end

    create_table :references do |t|
      t.integer :advisory_id, null: false
      t.text :url
      t.timestamps

      t.index :advisory_id
    end
  end

  def down
    drop_table :references

    drop_table :vulnerabilities

    add_index :advisories, :withdrawn_at
    add_index :advisories, :severity
    add_index :advisories, :created_at
    add_index :advisories, :updated_at
  end
end
