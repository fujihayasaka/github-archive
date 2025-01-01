# typed: true

class AddArchivedAtToUsers < ActiveRecord::Migration[7.1]
  use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :users, :archived_at, :datetime, null: true, precision: 6
  end
end
