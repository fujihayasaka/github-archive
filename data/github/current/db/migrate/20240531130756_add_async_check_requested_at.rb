class AddAsyncCheckRequestedAt < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :token_scan_results_validation, bulk: true do |t|
      t.datetime :async_check_requested_at, null: true, precision: 3, comment: "when an async on demand check was requested for this token. can be null. only some tokens have an async process."
      t.datetime :last_check_completed_at, null: true, precision: 3, comment: "when the last on demand check for this token was completed. can be null because for some tokens an async check can be requested before a scheduled check."
    end
  end
end
