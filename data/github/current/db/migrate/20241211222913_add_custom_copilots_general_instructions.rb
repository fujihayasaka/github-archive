# typed: true

class AddCustomCopilotsGeneralInstructions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    add_column :custom_copilots, :general_instructions, :text, null: true
  end
end
