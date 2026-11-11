# typed: true
# frozen_string_literal: true

class ChangeIssueLinksIdVIndexToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :issue_links_id_ks_idx, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :issue_links_id_ks_idx, bulk: true do |t|
      t.change :id, :int, null: false
    end
  end
end
