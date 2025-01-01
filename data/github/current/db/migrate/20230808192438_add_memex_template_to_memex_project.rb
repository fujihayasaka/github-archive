# typed: true
class AddMemexTemplateToMemexProject < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_projects, bulk: true do |t|
      t.belongs_to :created_with_memex_template, null: true, index: false, type: :bigint, unsigned: true, after: :id
    end
  end
end
