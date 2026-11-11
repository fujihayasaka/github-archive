class ChangePullRequestReviewCommentsIdKsIdxIdToBigint < ActiveRecord::Migration[8.2]
  use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_column :pull_request_review_comments_id_ks_idx,
                  :id,
                  :bigint,
                  unsigned: true,
                  null: false

    change_column :archived_pull_request_review_comments_id_ks_idx,
                  :id,
                  :bigint,
                  unsigned: true,
                  null: false
  end

  def down
    change_column :pull_request_review_comments_id_ks_idx,
                  :id,
                  :integer,
                  unsigned: true,
                  null: false

    change_column :archived_pull_request_review_comments_id_ks_idx,
                  :id,
                  :integer,
                  unsigned: true,
                  null: false
  end
end
