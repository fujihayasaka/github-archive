# typed: true
# frozen_string_literal: true

class CreateCheckSuiteRetention < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :check_suite_retention, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :check_suite_id, null: false, unsigned: true
      t.datetime :delete_at, null: false, precision: 6

      t.timestamps null: false, precision: 6

      t.index :check_suite_id, unique: true
      t.index [:delete_at, :repository_id, :check_suite_id]
    end

    add_vindex :check_suite_retention, :hash, :repository_id
    add_vindex :check_suite_retention, :check_suites_id_keyspace_idx, :check_suite_id
    add_auto_increment :check_suite_retention, :id, :check_suite_retention_id_seq
  end
end
