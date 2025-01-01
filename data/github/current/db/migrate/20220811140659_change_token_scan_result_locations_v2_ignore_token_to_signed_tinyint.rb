# typed: true
class ChangeTokenScanResultLocationsV2IgnoreTokenToSignedTinyint < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:token_scan_result_locations_v2, bulk: true) do |t|
      t.change :ignore_token, "tinyint(1)", null: false, default: 0, comment: "boolean; true if this location should be ignored. This value is set by customers secret-scanning paths-ignore configuration."
    end
  end

  def down
    change_table(:token_scan_result_locations_v2, bulk: true) do |t|
      t.change :ignore_token, "tinyint(1) unsigned", null: false, default: 0, comment: "boolean; true if this location should be ignored. This value is set by customers secret-scanning paths-ignore configuration."
    end
  end
end
