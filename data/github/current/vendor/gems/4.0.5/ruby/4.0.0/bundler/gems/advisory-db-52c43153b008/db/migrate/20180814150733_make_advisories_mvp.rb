# frozen_string_literal: true

class MakeAdvisoriesMvp < ActiveRecord::Migration[5.1]
  def up
    remove_index :advisories, :identifier
    rename_column :advisories, :identifier, :cve_id
    change_column :advisories, :cve_id, :string, limit: 40
    change_column_null :advisories, :cve_id, true
    add_index :advisories, :cve_id, unique: true

    rename_column :advisories, :title, :summary

    remove_column :advisories, :platform
    remove_column :advisories, :cvssv2
    remove_column :advisories, :cvssv3
    remove_column :advisories, :ingestion_state
    remove_column :advisories, :rejection_reason
    remove_column :advisories, :relevance_score
    remove_column :advisories, :raw_data
    remove_column :advisories, :source
    remove_column :advisories, :source_changed
    remove_column :advisories, :cpe22_uris
    remove_column :advisories, :cpe23_uris
    remove_column :advisories, :references
    remove_column :advisories, :published_date
    remove_column :advisories, :last_modified_date
  end

  def down
    remove_index :advisories, :cve_id
    rename_column :advisories, :cve_id, :identifier
    change_column :advisories, :identifier, :string, limit: nil
    change_column_null :advisories, :identifier, false
    add_index :advisories, :identifier, unique: true

    rename_column :advisories, :summary, :title

    add_column :advisories, :platform, :string
    add_column :advisories, :cvssv2, :decimal, precision: 3, scale: 1
    add_column :advisories, :cvssv3, :decimal, precision: 3, scale: 1
    add_column :advisories, :ingestion_state, :integer, default: 0, null: false
    add_column :advisories, :rejection_reason, :string
    add_column :advisories, :relevance_score, :integer
    add_column :advisories, :raw_data, :text, limit: 16.megabytes - 1
    add_column :advisories, :source, :integer, default: 0, null: false
    add_column :advisories, :source_changed, :boolean, default: false, null: false
    add_column :advisories, :cpe22_uris, :text
    add_column :advisories, :cpe23_uris, :text
    add_column :advisories, :references, :text
    add_column :advisories, :published_date, :datetime
    add_column :advisories, :last_modified_date, :datetime
  end
end
