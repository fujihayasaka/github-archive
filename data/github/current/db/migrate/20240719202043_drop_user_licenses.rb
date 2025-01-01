# typed: true

# rubocop:disable GitHub/MigrationCrossSchemaDomainConnection

class DropUserLicenses < ActiveRecord::Migration[8.0]

  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    drop_table :user_licenses, if_exists: true
  end
end
