class ChangePullRequestReviewThreadsIdKsIdxIdToBigint < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_column :pull_request_review_threads_id_ks_idx,
                  :id,
                  :bigint,
                  unsigned: true,
                  null: false

    change_column :archived_pull_request_review_threads_id_ks_idx,
                  :id,
                  :bigint,
                  unsigned: true,
                  null: false
  end

  def down
    change_column :pull_request_review_threads_id_ks_idx,
                  :id,
                  :integer,
                  null: false

    change_column :archived_pull_request_review_threads_id_ks_idx,
                  :id,
                  :integer,
                  null: false
  end
end
