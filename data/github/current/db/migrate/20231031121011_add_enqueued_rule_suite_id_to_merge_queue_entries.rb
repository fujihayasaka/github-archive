# typed: true
class AddEnqueuedRuleSuiteIdToMergeQueueEntries < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    add_column :merge_queue_entries, :enqueued_rule_suite_id, :bigint, unsigned: true, null: true, default: nil
  end
end
