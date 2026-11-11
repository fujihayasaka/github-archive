# typed: true
# frozen_string_literal: true

class RemoveSeatsFromCustomers < ActiveRecord::Migration[8.0] # rubocop:disable GitHub/ConnectionClassPresentInMigration
  def change
    remove_column :customers, :seats, :integer
  end
end
