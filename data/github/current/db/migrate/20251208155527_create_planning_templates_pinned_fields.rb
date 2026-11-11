# typed: true

class CreatePlanningTemplatesPinnedFields < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::IssuesPullRequests

  def change
    create_table :planning_templates_pinned_fields, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :planning_template_id, null: false, unsigned: true
      t.bigint :owner_id, null: false, unsigned: true
      t.bigint :issue_field_id, null: false, unsigned: true
      t.integer :position, null: false, unsigned: true

      t.index [:owner_id, :planning_template_id, :issue_field_id], unique: true, name: "uniq_owner_pt_field"
      t.index [:owner_id, :planning_template_id, :position], unique: true, name: "uniq_owner_pt_position"

      t.timestamps
    end

    add_vindex :planning_templates_pinned_fields, :hash, :owner_id

    add_auto_increment :planning_templates_pinned_fields, :id, :planning_templates_pinned_fields_id_seq
  end
end
