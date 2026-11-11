# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddOrganizationIdAndCreatedAtIndicesToSoftDeletedOrganizations < ActiveRecord::Migration[7.2]
  def change
    change_table :soft_deleted_organizations, bulk: true do |t|
      t.index [:organization_id], unique: true, name: "index_soft_deleted_organizations_on_organization_id"
      t.index [:created_at], name: "index_soft_deleted_organizations_on_created_at"
    end
  end
end
