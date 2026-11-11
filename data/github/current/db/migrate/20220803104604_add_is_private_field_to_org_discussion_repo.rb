# typed: true

class AddIsPrivateFieldToOrgDiscussionRepo < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :organization_discussion_repositories, bulk: true do |t|
      t.column :private, :boolean, default: false, null: false
      t.index [:organization_id, :private], name: "idx_org_discussion_repositories_on_org_id_and_private"
      t.remove_index [:organization_id], name: "index_organization_discussion_repositories_on_organization_id"
    end
  end
end
