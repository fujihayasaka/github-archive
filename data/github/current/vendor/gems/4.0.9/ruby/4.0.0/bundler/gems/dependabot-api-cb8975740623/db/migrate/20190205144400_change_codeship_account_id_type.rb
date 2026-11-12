# frozen_string_literal: true

class ChangeCodeshipAccountIdType < ActiveRecord::Migration[6.0]
  def change
    remove_column :codeship_accounts, :codeship_id, :uuid
    add_column :codeship_accounts, :codeship_id, :bigint

    add_index :codeship_accounts, :codeship_id, unique: true
  end
end
