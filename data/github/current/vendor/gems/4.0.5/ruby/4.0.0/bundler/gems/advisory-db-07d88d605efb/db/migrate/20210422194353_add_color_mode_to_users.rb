# frozen_string_literal: true

class AddColorModeToUsers < ActiveRecord::Migration[6.1]
  def change
    add_column :users, :color_mode, :string, limit: 10
  end
end
