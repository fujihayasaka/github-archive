# typed: true

class CustomPatternsPushProtectionFlag < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.column :push_protection_enabled, "tinyint(1)", null: false, default: 0, comment: "boolean flag indicating if push protection is enabled for this custom pattern"
    end
  end

  def down
    change_table(:secret_scan_custom_patterns, bulk: true) do |t|
      t.remove :push_protection_enabled
    end
  end
end
