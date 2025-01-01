# typed: true
# frozen_string_literal: true

class DependabotAutofixAnnotations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)
  def change
    create_table :dependabot_autofix_annotations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :check_annotation_id, null: false, unsigned: true
      t.bigint :autofix_job_id, null: false, unsigned: true
      t.bigint :repository_id, null: false, unsigned: true
      t.bigint :check_run_id, null: false, unsigned: true

      t.index :check_annotation_id, unique: true, name: "index_dependabot_autofix_annotations_on_check_annotation_id"
      t.index [:repository_id, :autofix_job_id, :check_run_id], name: "index_dep_autofix_ann_on_repo_autofix_and_check_run"

      t.timestamps
    end

    add_vindex :dependabot_autofix_annotations, :hash, :repository_id
  end
end
