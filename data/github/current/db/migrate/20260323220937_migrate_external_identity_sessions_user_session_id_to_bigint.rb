# typed: strict
# frozen_string_literal: true

class MigrateExternalIdentitySessionsUserSessionIdToBigint < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  sig { void }
  def up
    change_table :external_identity_sessions, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, null: false, auto_increment: true
      t.change :user_session_id, :bigint, unsigned: true, null: false
      t.change :external_identity_id, :bigint, unsigned: true, null: false
    end
  end

  sig { void }
  def down
    change_table :external_identity_sessions, bulk: true do |t|
      t.change :id, :integer, null: false, auto_increment: true
      t.change :user_session_id, :integer, null: false
      t.change :external_identity_id, :integer, null: false
    end
  end
end
