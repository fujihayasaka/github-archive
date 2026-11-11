# typed: true

class DropNameFromProfiles < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    remove_column :profiles, :name, :string, if_exists: true
  end
end
