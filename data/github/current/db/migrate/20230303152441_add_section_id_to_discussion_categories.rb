# typed: true

class AddSectionIdToDiscussionCategories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Discussions)

  def change
    change_table :discussion_categories, bulk: true do |t|
      t.column :discussion_section_id, :bigint, unsigned: true, null: true
      t.index :discussion_section_id
    end
  end
end
