# frozen_string_literal: true

class DropIndividualAffectedProductColumnsFromCVERequests < ActiveRecord::Migration[6.1]
  def change
    remove_column :cve_requests, :patches, :binary, limit: 1024
    remove_column :cve_requests, :affected_versions, :binary, limit: 1024
    remove_column :cve_requests, :package, :binary, limit: 100
    remove_column :cve_requests, :ecosystem, :binary, limit: 50
  end
end
