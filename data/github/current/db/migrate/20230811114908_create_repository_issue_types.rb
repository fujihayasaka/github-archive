class CreateRepositoryIssueTypes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :repository_issue_types, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, :bigint, unsigned: true, null: false
      t.column :issue_type_id, :bigint, unsigned: true, null: false
      t.column :enabled, :boolean, default: true, null: false

      t.timestamps
    end

    add_vindex :repository_issue_types, :hash, :repository_id

    add_auto_increment(:repository_issue_types, :id, :repository_issue_types_id_seq)
  end
end
