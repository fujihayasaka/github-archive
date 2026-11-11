# typed: true
# frozen_string_literal: true

class AddNumberToPullRequestStacks < ActiveRecord::Migration[8.2]
  use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    change_table :pull_request_stacks, bulk: true do |t|
      t.column :number, :bigint, unsigned: true, null: true, default: nil
      t.index [:repository_id, :number], unique: true
    end
  end
end
