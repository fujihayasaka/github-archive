# frozen_string_literal: true

class RemoveRepositoryAccessesAccountId < ActiveRecord::Migration[6.0]
  def change
    remove_index :repository_accesses, :account_id
  end
end
