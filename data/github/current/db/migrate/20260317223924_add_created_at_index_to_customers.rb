# typed: strict
# frozen_string_literal: true

class AddCreatedAtIndexToCustomers < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def change
    add_index :customers, :created_at, if_not_exists: true
  end
end
