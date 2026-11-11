# frozen_string_literal: true

class AddCredentialsTokenToUpdateJob < ActiveRecord::Migration[6.0]
  def change
    add_column :update_jobs, :hashed_credentials_token, :string
  end
end
