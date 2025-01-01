# typed: true
# frozen_string_literal: true

class DropArchivedDiscussionCategories < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :archived_discussion_categories, if_exists: true
  end
end
