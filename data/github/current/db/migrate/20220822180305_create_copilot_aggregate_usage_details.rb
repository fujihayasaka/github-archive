# typed: true
class CreateCopilotAggregateUsageDetails < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_aggregate_usage_details, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :user,                  null: false, index: true
      t.references :organization,          null: true, index: true
      t.references :repository,            null: true, index: false
      t.text       :remote_repository,     null: true, comment: "The remote repository URL"
      t.string     :editor_details,        null: true, limit: 80, index: true, comment: "The version of the editor used by the user"
      t.date       :usage_date,            null: true, index: true, comment: "Date for which usage was reported"
      t.integer    :usage_hour,            null: true, index: true, comment: "Hour for which usage was reported"
      t.integer    :usage_count,           null: true, default: 0, comment: "Number of times the user used the editor on this date in this hour"

      t.timestamps
    end
  end
end
