# typed: true
# frozen_string_literal: true

class RemoveIndexRepositorySecurityCenterStatusesOrganizationId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    remove_index :repository_security_center_statuses, :organization_id, name: "index_repository_security_center_statuses_organization_id"
  end
end
