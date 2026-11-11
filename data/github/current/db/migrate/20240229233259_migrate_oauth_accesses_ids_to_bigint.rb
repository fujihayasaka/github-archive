# typed: true
# frozen_string_literal: true

class MigrateOauthAccessesIdsToBigint < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :oauth_accesses, bulk: true do |t|
      t.change :id,               :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_id,          :bigint, null: false
      t.change :application_id,   :bigint, null: false
      t.change :authorization_id, :bigint
    end
  end
end
