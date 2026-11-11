# typed: true

class CreatePlaningTemplatesTypeFieldsMappings < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :planning_templates_type_fields_mappings, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :planning_template_id, null: false, unsigned: true
      t.bigint :owner_id, null: false, unsigned: true
      t.bigint :issue_type_id, null: false, unsigned: true
      t.bigint :issue_field_id, null: false, unsigned: true
      t.integer :position, null: false, unsigned: true

      t.index [:owner_id, :planning_template_id, :issue_type_id, :issue_field_id], unique: true, name: "uniq_owner_pt_issue_type_field"
      t.index [:owner_id, :planning_template_id, :issue_type_id, :position], unique: true, name: "uniq_owner_pt_issue_type_position"

      t.timestamps
    end

    add_vindex :planning_templates_type_fields_mappings, :hash, :owner_id

    add_auto_increment :planning_templates_type_fields_mappings, :id, :planning_templates_type_fields_mapping_id_seq
  end
end
