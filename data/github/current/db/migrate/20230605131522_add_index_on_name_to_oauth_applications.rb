# typed: true
class AddIndexOnNameToOauthApplications < ActiveRecord::Migration[7.1]
  def change
    add_index :oauth_applications, :name, unique: false
  end
end
