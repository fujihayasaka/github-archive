# typed: true
# frozen_string_literal: true

class DropOrganizationSecurityCenterStatuses < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    drop_table :organization_security_center_statuses, if_exists: true
  end
end
