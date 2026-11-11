# typed: true

class CreateEnterprisePublicMonitoringAlerts < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :enterprise_public_monitoring_alerts, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint   :business_id,          null: false, unsigned: true, comment: "an enterprise mapped to the secret author at the time of detection"
      t.bigint   :token_scan_result_id, null: false, unsigned: true, comment: "the alert referencing the secret detected in the public repository"
      t.bigint   :secret_author_id,     null: false, unsigned: true, comment: "author of the secret detected in the alert"
      t.bigint   :repository_id,        null: false, unsigned: true, comment: "id of the public repository where the secret was detected"
      t.datetime :created_at,           null: false, precision: 6, comment: "when the attribution was recorded; used for pagination"

      t.index [:business_id, :token_scan_result_id], unique: true, name: "idx_business_token_scan_result"
      t.index [:business_id, :created_at, :token_scan_result_id], name: "idx_business_created_at", comment: "supports ordering and cursor-based pagination by creation time within an enterprise"
      t.index [:business_id, :repository_id], name: "idx_business_repository"
      t.index [:business_id, :secret_author_id], name: "idx_business_author"
    end
  end
end
