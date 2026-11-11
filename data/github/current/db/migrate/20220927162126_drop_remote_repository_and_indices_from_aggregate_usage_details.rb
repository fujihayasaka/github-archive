# typed: true

class DropRemoteRepositoryAndIndicesFromAggregateUsageDetails < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    change_table :copilot_aggregate_usage_details, bulk: true do |t|
      # transition from this text column to a foreign key
      # We have no model implementing this column so removing it from airflow sources is all that is needed
      t.remove :remote_repository
      t.column :blocked_remote_repository_id, :bigint, unsigned: true, null: false, default: 0, after: :repository_id, comment: "reference to blocked remote repository_id if it exists or zero if it doesn't"

      # these should be 0 if they don't exist because NULL makes indices sad
      t.change :organization_id, :bigint, unsigned: true, null: false, default: 0
      t.change :repository_id, :bigint, unsigned: true, null: false, default: 0

      # these are all going to be part of the aggregate index
      t.remove_index name: "index_copilot_aggregate_usage_details_on_user_id"


      # this is the aggregate index
      t.index [:user_id, :organization_id, :repository_id, :blocked_remote_repository_id, :editor_details, :usage_date, :usage_hour], name: "index_aggregate_on_everything", unique: true
    end
  end
end
