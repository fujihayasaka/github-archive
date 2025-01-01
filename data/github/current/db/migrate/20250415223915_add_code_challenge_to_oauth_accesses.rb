# typed: true
# frozen_string_literal: true

class AddCodeChallengeToOauthAccesses < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    add_column :oauth_accesses, :code_challenge, :string, limit: 44, null: true
  end
end
