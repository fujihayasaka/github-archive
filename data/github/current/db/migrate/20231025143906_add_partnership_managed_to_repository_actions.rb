class AddPartnershipManagedToRepositoryActions < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :repository_actions, :partnership_managed, :boolean, null: true, default: false
  end
end
