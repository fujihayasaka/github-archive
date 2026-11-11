# frozen_string_literal: true

class RemoveNotNullConstraintFromCVERequestIndividualAffectedProductColumns < ActiveRecord::Migration[6.1]
  def change
    change_column_null :cve_requests, :ecosystem, true
    change_column_null :cve_requests, :package, true
    change_column_null :cve_requests, :affected_versions, true
    change_column_null :cve_requests, :patches, true
  end
end
