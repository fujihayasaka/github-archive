# typed: true

class AddLockedAtToCustomer < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :customers, :locked_at, :datetime, null: true, precision: 6
  end
end
