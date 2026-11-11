class CreateIssueTypes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_types, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, :bigint, unsigned: true, null: false
      t.column :issue_type, :tinyint, unsigned: true, null: false
      t.column :enabled, :boolean, default: true, null: false
      t.column :private, :boolean, default: false, null: false
      t.column :name, "varbinary(512)", null: false
      t.column :description, "varbinary(1024)", null: true
      t.column :color, :tinyint, unsigned: true, null: false

      t.timestamps
    end

    add_vindex :issue_types, :hash, :owner_id

    add_auto_increment(:issue_types, :id, :issue_types_id_seq)
  end
end
