# typed: true
# frozen_string_literal: true

class AddDisplayNameToReminder < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Reminders)
  def change
    add_column :reminders, :display_name, :string, null: true, limit: 80
  end
end
