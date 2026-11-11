# typed: true
# frozen_string_literal: true

require "github/transitions/20240807092039_copy_rollup_summaries"

class CopyRollupSummariesTransition < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::NotificationsEntries)

  def up # rubocop:disable GitHub/OneTablePerMigration
    return if !GitHub.enterprise? && !Rails.env.development?

    add_index :notification_entries, :summary_id, if_not_exists: true
    add_index :saved_notification_entries, :summary_id, if_not_exists: true

    begin
      arguments = GitHub::Transitions::Arguments.new(dry_run: false)
      transition = GitHub::Transitions::CopyRollupSummaries.new(arguments)
      transition.run
    ensure
      remove_index :notification_entries, :summary_id, if_exists: true
      remove_index :saved_notification_entries, :summary_id, if_exists: true
    end
  end

  def down
  end
end
