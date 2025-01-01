# typed: true
class AddAdvancedSecurityEnabledToGhasRepositoryContributions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::BillingCollab)

  def change
    add_column :ghas_repository_contributions, :advanced_security_enabled, :boolean, null: true
  end
end
