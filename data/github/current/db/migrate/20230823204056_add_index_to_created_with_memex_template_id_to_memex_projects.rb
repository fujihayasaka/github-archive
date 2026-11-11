class AddIndexToCreatedWithMemexTemplateIdToMemexProjects < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Memexes

  def change
    change_table :memex_projects, bulk: true do |t|
      t.index :created_with_memex_template_id
    end
  end
end
