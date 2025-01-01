# frozen_string_literal: true

class AddUserModel < ActiveRecord::Migration[6.0]
  def change
    create_table :users do |t|
      t.string :login, null: false, limit: 40

      t.timestamps
    end

    add_index :users, :login, unique: true
  end
end
