# typed: true

class AddDeletedAtToRepositories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repositories, :deleted_at, :datetime, precision: 6
  end
end
