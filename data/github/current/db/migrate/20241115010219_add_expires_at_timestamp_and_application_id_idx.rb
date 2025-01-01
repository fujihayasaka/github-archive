# typed: true

class AddExpiresAtTimestampAndApplicationIdIdx < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::Integrations

  def change
    add_index :oauth_accesses, [:expires_at_timestamp, :application_id], name: "index_oauth_accesses_on_expires_at_timestamp_and_application_id" # rubocop:disable GitHub/AvoidRedundantIndex
  end
end
