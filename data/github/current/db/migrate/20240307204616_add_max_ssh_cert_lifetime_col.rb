class AddMaxSshCertLifetimeCol < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :ssh_certificate_authorities, :max_ssh_cert_lifetime_hours, :integer, null: true
  end
end
