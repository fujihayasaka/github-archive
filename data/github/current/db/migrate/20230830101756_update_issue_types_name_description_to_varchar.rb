class UpdateIssueTypesNameDescriptionToVarchar < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    connection.execute(<<~SQL)
      ALTER TABLE issue_types
        MODIFY COLUMN `name` VARCHAR(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
        MODIFY COLUMN `description` VARCHAR(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL;
    SQL
  end

  def down
    connection.execute(<<~SQL)
      ALTER TABLE issue_types
        MODIFY COLUMN `name` VARBINARY(512) NOT NULL,
        MODIFY COLUMN `description` VARBINARY(1024) DEFAULT NULL;
    SQL
  end
end
