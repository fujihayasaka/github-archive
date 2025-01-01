class CreateReachabilityAnalysisStatusUpdates < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Vulnerabilities)

  def change
    create_table :reachability_analysis_status_updates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :reachability_analysis_id, unsigned: true, null: false, index: true
      t.column :status, :tinyint, unsigned: true, default: 0
      t.column :metadata, :json, null: true

      t.timestamps
    end
  end
end
