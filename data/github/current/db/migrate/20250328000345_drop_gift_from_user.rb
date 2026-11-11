# typed: true
# frozen_string_literal: true

class DropGiftFromUser < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    remove_column :users, :gift, :boolean, null: true
  end
end
