# frozen_string_literal: true

class CVERequestColumnsToVarbinary < ActiveRecord::Migration[5.2]
  def up
    change_column :cve_requests, :title, "varbinary(1024)", null: false
    change_column :cve_requests, :ecosystem, "varbinary(50)", null: false
    change_column :cve_requests, :package, "varbinary(100)", null: false
    change_column :cve_requests, :affected_versions, "varbinary(100)", null: false
    change_column :cve_requests, :patches, "varbinary(100)", null: false
  end

  def down
    change_column :cve_requests, :title, "varchar(1024)", null: false
    change_column :cve_requests, :ecosystem, "varchar(50)", null: false
    change_column :cve_requests, :package, "varchar(100)", null: false
    change_column :cve_requests, :affected_versions, "varchar(100)", null: false
    change_column :cve_requests, :patches, "varchar(100)", null: false
  end
end
