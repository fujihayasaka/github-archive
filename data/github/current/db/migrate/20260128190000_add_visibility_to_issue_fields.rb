# typed: true
# frozen_string_literal: true

class AddVisibilityToIssueFields < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_column :issue_fields, :visibility, :integer, limit: 1, null: false, default: 0
  end
end
