# typed: true

class UpdateReviewRequestsCharacterSet < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE review_requests
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
    SQL

    connection.execute(<<~SQL)
      ALTER TABLE archived_review_requests
      CONVERT TO
        CHARACTER SET utf8mb4
        COLLATE utf8mb4_unicode_520_ci
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE review_requests
      CONVERT TO
        CHARACTER SET utf8mb3
        COLLATE utf8mb3_general_ci
    SQL

    connection.execute(<<~SQL)
      ALTER TABLE archived_review_requests
      CONVERT TO
        CHARACTER SET utf8mb3
        COLLATE utf8mb3_general_ci
    SQL
  end
end
