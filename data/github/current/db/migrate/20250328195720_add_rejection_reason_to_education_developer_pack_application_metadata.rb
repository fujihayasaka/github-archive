# typed: true

class AddRejectionReasonToEducationDeveloperPackApplicationMetadata < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :education_developer_pack_application_metadata, :rejection_reason, :text, default: nil, null: true
  end
end
