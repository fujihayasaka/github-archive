# typed: true
# frozen_string_literal: true

class UpdateSecretScanCustomPatternsSecretTypeDefault < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_column_null :secret_scan_custom_patterns, :secret_type, true
  end

  def down
    change_column_null :secret_scan_custom_patterns, :secret_type, false
  end
end
