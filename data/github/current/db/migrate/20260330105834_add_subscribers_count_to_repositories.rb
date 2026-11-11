# typed: true

class AddSubscribersCountToRepositories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repositories, :subscribers_count, :integer, null: false, default: 0
  end
end
