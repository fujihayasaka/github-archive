# typed: true
# frozen_string_literal: true

class UpgradeIntToBigintOnTwoFactorRecoveryRequests < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :two_factor_recovery_requests, bulk: true do |t|
      t.change :id,                      :bigint, null: false, auto_increment: true
      t.change :user_id,                 :bigint, null: false
      t.change :oauth_access_id,         :bigint
      t.change :authenticated_device_id, :bigint
      t.change :public_key_id,           :bigint
      t.change :reviewer_id,             :bigint
      t.change :requesting_device_id,    :bigint
    end
  end

  def down
    change_table :two_factor_recovery_requests, bulk: true do |t|
      t.change :id,                      :int, null: false, auto_increment: true
      t.change :user_id,                 :int, null: false
      t.change :oauth_access_id,         :int
      t.change :authenticated_device_id, :int
      t.change :public_key_id,           :int
      t.change :reviewer_id,             :int
      t.change :requesting_device_id,    :int
    end
  end
end
