# typed: true
# frozen_string_literal: true

class ChangeIssueFieldOptionsNonNullColumns < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    # Set default values and update existing null values
    update_sql = <<~SQL
      UPDATE issue_field_options
      SET priority = COALESCE(priority, 0),
          color = COALESCE(color, 0)
    SQL
    execute(update_sql)

    # Make columns non-null and set defaults in a single operation
    change_table :issue_field_options, bulk: true do |t|
      t.change :priority, :integer, null: false, default: 0
      t.change :color, :integer, null: false, default: 0
    end
  end

  def down
    change_table :issue_field_options, bulk: true do |t|
      t.change :priority, :integer, null: true, default: nil
      t.change :color, :integer, null: true, default: nil
    end
  end
end
