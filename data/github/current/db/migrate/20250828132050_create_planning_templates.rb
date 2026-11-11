# typed: true

class CreatePlanningTemplates < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :planning_templates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :owner_id, null: false, unsigned: true
      t.string :name, null: false, limit: 64
      t.string :description, limit: 256, null: true
      t.integer :template_type, limit: 1, null: false, default: 0

      t.index [:owner_id, :name], unique: true, name: "index_planning_templates_on_owner_id_name"

      t.timestamps
    end

    add_vindex :planning_templates, :hash, :owner_id

    add_auto_increment :planning_templates, :id, :planning_templates_id_seq
  end
end
