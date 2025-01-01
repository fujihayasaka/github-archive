# typed: true
# frozen_string_literal: true

class CreateIssueFieldOptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_field_options, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :owner_id, unsigned: true, null: false
      t.bigint   :issue_field_id, unsigned: true, null: false
      t.string   :name, limit: 255, null: false
      t.string   :description, limit: 255, null: true
      t.bigint  :priority, null: true
      t.integer :color, null: true

      t.timestamps
    end

    add_vindex :issue_field_options, :hash, :owner_id

    # Auto increment for "owner" table. The sequence table needs to exist before this migration is run.
    add_auto_increment :issue_field_options, :id, :issue_field_options_id_seq
  end
end
