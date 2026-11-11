# typed: true
# frozen_string_literal: true

class AddIndexToProductUuidsOnMetered < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_index :product_uuids, :metered
  end
end
