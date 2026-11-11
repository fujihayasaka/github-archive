# frozen_string_literal: true

class AddEventSourceColumnToAccounts < ActiveRecord::Migration[6.0]
  def change
    add_column :accounts,
               :event_source,
               :integer,
               null: false,
               default: 0
  end
end
