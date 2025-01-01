class AddHasOrcidRecordToUserMetadata < ActiveRecord::Migration[7.2]
  def change
    add_column :user_metadata, :has_orcid_record, :boolean, null: false, default: false
  end
end
