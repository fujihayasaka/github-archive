# typed: true
# frozen_string_literal: true

class UpdateXrefsSourceAndTargetTypes < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def up
    execute <<-SQL
      ALTER TABLE cross_references CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci,
      MODIFY COLUMN `source_type` enum('Issue', 'Discussion', 'Team', 'Milestone') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL,
      MODIFY COLUMN `target_type` enum('Issue', 'Discussion', 'Team', 'Milestone') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL;
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE cross_references CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci,
      MODIFY COLUMN `source_type` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL,
      MODIFY COLUMN `target_type` varchar(255) CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci NOT NULL;
    SQL
  end
end
