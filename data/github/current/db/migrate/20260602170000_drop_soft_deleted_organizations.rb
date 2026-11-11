# typed: true
# frozen_string_literal: true

class DropSoftDeletedOrganizations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    drop_table :soft_deleted_organizations, if_exists: true
  end
end
