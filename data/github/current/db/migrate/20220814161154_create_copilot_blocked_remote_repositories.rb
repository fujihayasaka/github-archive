# typed: true
class CreateCopilotBlockedRemoteRepositories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_blocked_remote_repositories, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.text   :repository_remote, null: false, comment: "The remote repository URL"
      t.bigint   :org_id, unsigned: true, null: false, index: { unique: false }, comment: "The organization"
      t.bigint   :user_id, unsigned: true, null: false, index: false, comment: "The user who last updated the record"
      t.timestamps
    end
  end
end
