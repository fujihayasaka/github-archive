# typed: true

class AddOwnerIdToGhasRepositoryContributions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::BillingCollab)

  def change
    add_column :ghas_repository_contributions, :owner_id, :bigint, unsigned: true, null: true
  end
end
