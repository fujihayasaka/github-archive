class AddIndexOnOrganizationMemberExportsSubject < ActiveRecord::Migration[7.2]
  def change
    add_index :organization_members_exports, [:subject_id, :subject_type]
  end
end
