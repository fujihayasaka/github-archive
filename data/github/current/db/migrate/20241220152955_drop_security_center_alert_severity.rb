# typed: true
# frozen_string_literal: true

class DropSecurityCenterAlertSeverity < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    drop_table :security_center_alert_severities, if_exists: true
  end
end
