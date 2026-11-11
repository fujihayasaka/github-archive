# typed: true
# frozen_string_literal: true

class AddIndexToProfilesOnUserIdNameEmail < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :profiles, [:name, :email, :user_id], name: "index_profiles_on_name_email_user_id"
  end
end
