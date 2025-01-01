# typed: true

class SamlSessionsChangeIndexToUnique < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Users

  def up
    change_table(:saml_sessions, bulk: true) do |t|
      t.remove_index name: :index_saml_sessions_on_user_id
      t.index [:user_id], name: :index_saml_sessions_on_user_id, unique: true

      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :user_id, :bigint, unsigned: true
    end
  end

  def down
    change_table(:saml_sessions, bulk: true) do |t|
      t.remove_index name: :index_saml_sessions_on_user_id
      t.index [:user_id], name: :index_saml_sessions_on_user_id

      t.change :id, :int, auto_increment: true
      t.change :user_id, :int
    end
  end
end
