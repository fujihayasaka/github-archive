# typed: true
# frozen_string_literal: true

class AddIndexToOauthApplicationTransfersOnRequesterId < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up
    change_table :oauth_application_transfers, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :application_id, :bigint, unsigned: true, null: false
      t.change :requester_id, :bigint, unsigned: true, null: false
      t.change :responder_id, :bigint, unsigned: true
      t.change :target_id, :bigint, unsigned: true, null: false
      t.index :requester_id
    end
  end

  def down
    change_table :oauth_application_transfers, bulk: true do |t|
      t.remove_index :requester_id
      t.change :id, :integer, null: false, auto_increment: true
      t.change :application_id, :integer, null: false
      t.change :requester_id, :integer, null: false
      t.change :responder_id, :integer
      t.change :target_id, :integer, null: false
    end
  end
end
