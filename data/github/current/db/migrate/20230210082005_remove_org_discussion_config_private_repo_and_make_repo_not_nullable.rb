# typed: true

class RemoveOrgDiscussionConfigPrivateRepoAndMakeRepoNotNullable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def up
    change_table :organization_discussion_repositories, bulk: true do |t|
      t.remove_index :private_repository_id, name: "idx_org_discussion_repositories_on_private_repository_id"
      t.remove :private_repository_id, type: "BIGINT(20) UNSIGNED", null: true
      t.change :repository_id, "BIGINT(20) UNSIGNED", null: false
    end
  end

  def down
    change_table :organization_discussion_repositories, bulk: true do |t|
      t.add_index :private_repository_id, name: "idx_org_discussion_repositories_on_private_repository_id"
      t.column :private_repository_id, type: "BIGINT(20) UNSIGNED", null: true
      t.change :repository_id, "BIGINT(20) UNSIGNED", null: true
    end
  end
end
