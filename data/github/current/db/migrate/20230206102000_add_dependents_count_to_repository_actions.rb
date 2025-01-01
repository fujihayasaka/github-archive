# typed: true

class AddDependentsCountToRepositoryActions < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :repository_actions, :dependents_count, :bigint, null: true, default: nil
  end
end
