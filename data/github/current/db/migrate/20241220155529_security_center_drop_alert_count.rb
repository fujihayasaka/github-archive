# typed: true
# frozen_string_literal: true

class SecurityCenterDropAlertCount < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_security_center_statuses, bulk: true do |t|
      t.remove_index name: "index_owner_id_feature_scanning_status_scanning_count_repo_id"
      t.remove_index name: "index_business_id_feature_scanning_status_scanning_count_repo_id"
      t.remove :scanning_count

      # no indexes use :scanned_at
      t.remove :scanned_at
    end
  end
end
