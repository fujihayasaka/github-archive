class AddValidatedAtToUserPersonalProfiles < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :user_personal_profiles, :billing_address_validated_at, :datetime, precision: 6, default: nil
  end
end
