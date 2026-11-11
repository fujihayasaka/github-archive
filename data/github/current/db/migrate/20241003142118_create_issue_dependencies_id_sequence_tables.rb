# typed: true

# rubocop:disable GitHub/OneTablePerMigration

class CreateIssueDependenciesIdSequenceTables < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    create_table :issue_dependencies_id_seq, comment: "vitess_sequence", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, :bigint, primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :next_id, :bigint, unsigned: true
      t.column :cache, :bigint, unsigned: true
    end
    create_sequence(:issue_dependencies_id_seq)

    create_table :issue_dependency_orchestrations_id_seq, comment: "vitess_sequence", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, :bigint, primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :next_id, :bigint, unsigned: true
      t.column :cache, :bigint, unsigned: true
    end
    create_sequence(:issue_dependency_orchestrations_id_seq)

    create_table :issue_dependency_lists_id_seq, comment: "vitess_sequence", id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, :bigint, primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :next_id, :bigint, unsigned: true
      t.column :cache, :bigint, unsigned: true
    end
    create_sequence(:issue_dependency_lists_id_seq)
  end
end
