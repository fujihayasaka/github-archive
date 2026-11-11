# typed: true
# frozen_string_literal: true

class UpdateRefUpdateRequestsShaColumns < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :ref_update_requests, bulk: true do |t|
      t.change :before_sha, "varbinary(32)", null: true
      t.change :after_sha, "varbinary(32)", null: false
    end
  end

  def down
    change_table :ref_update_requests, bulk: true do |t|
      t.change :before_sha, "binary(20)", null: true
      t.change :after_sha, "binary(20)", null: false
    end
  end
end
