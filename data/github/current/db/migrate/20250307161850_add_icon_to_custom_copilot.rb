# typed: true

class AddIconToCustomCopilot < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :custom_copilots, bulk: true do |t|
      t.string :icon_type
      t.string :icon_color
    end
  end
end
