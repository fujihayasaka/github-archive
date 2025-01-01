# typed: true
class AddSubjectTypeColumnToPrReviewThreads < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_request_review_threads, bulk: true do |t|
      t.integer :subject_type, limit: 1, default: 0
      t.change :id, :bigint, unsigned: true
      t.change :pull_request_id, :bigint, unsigned: true
      t.change :pull_request_review_id, :bigint, unsigned: true
      t.change :resolver_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true
    end
  end

  def down
    change_table :pull_request_review_threads, bulk: true do |t|
      t.remove :subject_type
      t.change :id, :int
      t.change :pull_request_id, :int
      t.change :pull_request_review_id, :int
      t.change :resolver_id, :int
      t.change :repository_id, :int
    end
  end
end
