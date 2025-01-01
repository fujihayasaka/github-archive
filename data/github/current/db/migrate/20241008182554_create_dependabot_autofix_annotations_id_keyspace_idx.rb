# typed: true
# frozen_string_literal: true

class CreateDependabotAutofixAnnotationsIdKeyspaceIdx < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :dependabot_autofix_annotations_id_keyspace_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: true
    end

    # Shard the lookup vindex table by `id` column.
    # This allows efficient lookups by `id` column in the `dependabot_autofix_annotations` table
    add_vindex :dependabot_autofix_annotations_id_keyspace_idx, :hash, :id

    # Configure the `dependabot_autofix_annotations_id_keyspace_idx` lookup vindex
    # table to be maintained when new rows into `dependabot_autofix_annotations` are inserted
    create_vindex :dependabot_autofix_annotations_id_keyspace_idx, :lookup_unique, owner: "dependabot_autofix_annotations", from: "id", table: "dependabot_autofix_annotations_id_keyspace_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    # Set up the lookup `dependabot_autofix_annotations_id_keyspace_idx` lookup vindex to be
    # used for queries on `id` column of `dependabot_autofix_annotations` table
    add_vindex :dependabot_autofix_annotations, :dependabot_autofix_annotations_id_keyspace_idx, :id

    # Set up some secondary vindexes owned by other tables to be used for queries
    # on `check_run_id` and `check_annotation_id` columns of `dependabot_autofix_annotations` table
    add_vindex :dependabot_autofix_annotations, :check_runs_id_keyspace_idx, :check_run_id
    add_vindex :dependabot_autofix_annotations, :check_annotations_id_keyspace_idx, :check_annotation_id

    # Set up the previously created `dependabot_autofix_annotations_id_seq` sequence to be used
    # to generate `id` values when inserting rows into `dependabot_autofix_annotations`
    add_auto_increment(:dependabot_autofix_annotations, :id, :dependabot_autofix_annotations_id_seq)
  end
end
