# rubocop:disable GitHub/DoNotModifyAndDeleteCreateSameMigration
# typed: true
# frozen_string_literal: true

class CreateIssueFieldValues < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_field_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :repository_id, null: false, unsigned: true
      t.bigint   :issue_id, null: false, unsigned: true
      t.bigint   :issue_field_id, null: false, unsigned: true
      t.json :value
      t.integer  :data_type, limit: 1, null: false
      t.bigint   :actor_id, null: false, unsigned: true

      t.index [:repository_id, :issue_id], name: "index_issue_field_values_on_repository_id_issue_id"

      t.timestamps
    end

    add_vindex :issue_field_values, :hash, :repository_id

    add_auto_increment :issue_field_values, :id, :issue_field_values_id_seq
  end
end

# rubocop:enable GitHub/DoNotModifyAndDeleteCreateSameMigration
