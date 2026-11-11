# typed: true
# frozen_string_literal: true

class IncreaseOrgGrantRequestReasonLimit < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Permissions)

  def change
    change_column :organization_programmatic_access_grant_requests, :reason, "varchar(1024)", default: nil
  end
end
