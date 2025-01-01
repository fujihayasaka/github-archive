# typed: true
# frozen_string_literal: true

class IssueEventDetailsCharsetAndCollation < ActiveRecord::Migration[8.0]

  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    execute <<-SQL
      ALTER TABLE issue_event_details CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `label_color` VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `label_text_color` VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `subject_type` VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `ref` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `before_commit_oid` CHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `after_commit_oid` CHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `lock_reason` VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `project_previous_status` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `project_status` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
    SQL

    execute <<-SQL
      ALTER TABLE archived_issue_event_details CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `label_color` VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `label_text_color` VARCHAR(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `subject_type` VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `ref` VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `before_commit_oid` CHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `after_commit_oid` CHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `lock_reason` VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
      MODIFY COLUMN `project_previous_status` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `project_status` TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci;
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE issue_event_details CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `label_color` VARCHAR(6) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `label_text_color` VARCHAR(6) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `subject_type` VARCHAR(20) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `ref` VARCHAR(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `before_commit_oid` CHAR(40) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `after_commit_oid` CHAR(40) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `lock_reason` VARCHAR(30) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `project_previous_status` TEXT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `project_status` TEXT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
    SQL

    execute <<-SQL
      ALTER TABLE archived_issue_event_details CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `label_color` VARCHAR(6) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `label_text_color` VARCHAR(6) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `subject_type` VARCHAR(20) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `ref` VARCHAR(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `before_commit_oid` CHAR(40) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `after_commit_oid` CHAR(40) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `lock_reason` VARCHAR(30) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci DEFAULT NULL,
      MODIFY COLUMN `project_previous_status` TEXT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `project_status` TEXT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
    SQL
  end
end
