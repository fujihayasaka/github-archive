class CreateCopilotUsageMetrics < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_usage_metrics, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # we need to reference the business that this is under for fast lookups
      # additionally, organizations can be removed from businesses and this lookup is needed to
      # accurately calculate the usage metrics for a business at a given date
      t.references :business, index: { unique: false }, null: true, comment: "The business that this usage metric is under (if any)"

      # we need to reference the organization that this is under for fast lookups
      t.references :organization, index: { unique: false }, null: true, comment: "The organization that this usage metric is under"

      # language this usage metric is for
      t.references :language_name, index: { unique: false }, null: true, comment: "The language this usage metric is for"

      # date this usage metric is for
      t.date :date, null: false, comment: "The date this usage metric is for"

      # number of suggestions made
      t.integer :suggestions_count, null: false, default: 0, comment: "The number of suggestions made"

      # number of suggestions accepted
      t.integer :acceptances_count, null: false, default: 0, comment: "The number of suggestions accepted"

      # number of lines suggested
      t.integer :lines_suggested, null: false, default: 0, comment: "The number of lines suggested"

      # number of lines accepted
      t.integer :lines_accepted, null: false, default: 0, comment: "The number of lines accepted"

      # number of active users for this date
      t.integer :active_users, null: false, default: 0, comment: "The number of active users (have accepted at least one suggestion)"

      # editor will be an enum
      t.integer :editor, default: 0, null: false, comment: "The editor this usage metric is for"

      # metadata will be a JSON blob
      t.json :metadata, null: false, comment: "The metadata for this usage metric"

      t.timestamps
    end
  end
end
