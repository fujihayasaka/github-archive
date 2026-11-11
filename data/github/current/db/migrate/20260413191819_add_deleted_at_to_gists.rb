class AddDeletedAtToGists < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Gists)

  def change
    add_column :gists, :deleted_at, :datetime, precision: 6
  end
end
