# typed: true

class AddHandleIndexToWebauthnUserHandles < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :webauthn_user_handles, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :user_id, :bigint, unsigned: true
      t.index [:webauthn_user_handle, :user_id], name: "index_webauthn_user_handles_on_handle_and_user_id"
    end
  end

  def down
    change_table :webauthn_user_handles, bulk: true do |t|
      t.change :id, :int, auto_increment: true
      t.change :user_id, :int
      t.remove_index [:webauthn_user_handle, :user_id], name: "index_webauthn_user_handles_on_handle_and_user_id"
    end
  end
end
