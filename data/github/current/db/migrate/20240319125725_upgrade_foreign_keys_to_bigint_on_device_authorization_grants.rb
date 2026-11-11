# typed: true
# frozen_string_literal: true

class UpgradeForeignKeysToBigintOnDeviceAuthorizationGrants < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def up
    change_table :device_authorization_grants, bulk: true do |t|
      t.change :application_id,  :bigint, null: false
      t.change :oauth_access_id, :bigint
    end
  end

  def down
    change_table :device_authorization_grants, bulk: true do |t|
      t.change :application_id,  :int, null: false
      t.change :oauth_access_id, :int
    end
  end
end
