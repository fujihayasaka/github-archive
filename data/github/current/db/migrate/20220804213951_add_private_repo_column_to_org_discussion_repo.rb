# typed: true

class AddPrivateRepoColumnToOrgDiscussionRepo < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_column_null :organization_discussion_repositories, :repository_id, true

    change_table :organization_discussion_repositories, bulk: true do |t|
      t.bigint :private_repository_id, null: true, unsigned: true
      t.index :private_repository_id, name: "idx_org_discussion_repositories_on_private_repository_id"
      t.index :organization_id, name: "index_organization_discussion_repositories_on_organization_id", unique: true
      t.remove :private
      t.remove_index name: "idx_org_discussion_repositories_on_org_id_and_private"
    end
  end
end
