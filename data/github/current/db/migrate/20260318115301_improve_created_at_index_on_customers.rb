# typed: strict
# frozen_string_literal: true

class ImproveCreatedAtIndexOnCustomers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    change_table :customers, bulk: true do |t|
      t.index [:created_at, :billing_type, :locked_at]
      t.remove_index :created_at
    end
  end
end
