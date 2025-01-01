# typed: true

class DropCompromisedPasswordDatasourcesPasswords < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :compromised_password_datasources_passwords
  end
end
