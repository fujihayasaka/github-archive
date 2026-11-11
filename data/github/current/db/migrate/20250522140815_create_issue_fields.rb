# typed: true
# frozen_string_literal: true

class CreateIssueFields < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_fields, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :owner_id, unsigned: true, null: false
      t.string   :name, limit: 255, null: false
      t.string   :name_slug, limit: 255, null: false
      t.string   :description, limit: 255, null: true
      t.bigint   :priority, null: true
      t.json :default_value
      t.integer  :data_type, limit: 1, null: false
      t.bigint   :actor_id, null: false, unsigned: true

      t.index [:owner_id, :name_slug], unique: true, name: "index_issue_fields_on_owner_id_name_slug"

      t.timestamps
    end

    add_vindex :issue_fields, :hash, :owner_id

    # Auto increment for "owner" table. The sequence table needs to exist before this migration is run.
    add_auto_increment :issue_fields, :id, :issue_fields_id_seq
  end
end
