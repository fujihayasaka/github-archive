class DropSecurityOverviewHasSupportedLanguage < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    remove_column :repository_security_center_statuses, :has_supported_language
  end
end
