# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddIssueFieldIdColumnAndIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_columns, bulk: true do |t|
      t.bigint :issue_field_id, unsigned: true, null: false, default: 0

      t.index [:issue_field_id]
      t.index [:memex_project_id, :name_slug, :issue_field_id], unique: true
      t.remove_index [:memex_project_id, :name_slug], name: :index_memex_project_columns_on_project_and_name_slug, unique: true
    end
  end
end
