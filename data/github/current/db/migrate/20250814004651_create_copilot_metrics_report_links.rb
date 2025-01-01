class CreateCopilotMetricsReportLinks < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Copilot)
  def change
    create_table :copilot_metrics_report_links, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :business_id, null: false, comment: "The enterprise ID that this report belongs to", unsigned: true
      t.integer :report_type, null: false, limit: 1
      t.json :download_links, null: false, comment: "The blob storage URLs for downloading the report files"
      t.date :report_end_day, null: false, comment: "The end day of the report period"

      t.timestamps

      t.index [:business_id, :report_type], name: "index_copilot_metrics_report_links_unique", unique: true
    end
  end
end
