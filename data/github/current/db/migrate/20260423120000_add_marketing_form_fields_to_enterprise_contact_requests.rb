# typed: true

class AddMarketingFormFieldsToEnterpriseContactRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Site)

  def change
    change_table :enterprise_contact_requests, bulk: true do |t|
      t.column :short_custom_1, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :github_enterprise_cloud_set_up, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :ado_is_cloud_hosted, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
      t.column :using_git_or_version_control, :string, limit: 255, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci"
    end
  end
end
