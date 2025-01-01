# typed: true
class NullableOwnersOnMemexTemplates < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Memexes

  def change
    change_table :memex_templates, bulk: true do |t|
      t.change_null :owner_id, true
      t.change_null :owner_type, true
    end
  end
end
