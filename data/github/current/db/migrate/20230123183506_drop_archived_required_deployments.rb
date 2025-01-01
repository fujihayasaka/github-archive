# typed: true
# frozen_string_literal: true

class DropArchivedRequiredDeployments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    drop_table :archived_required_deployments, if_exists: true
  end
end
