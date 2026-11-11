# frozen_string_literal: true

class CreateRepositoryAccesses < ActiveRecord::Migration[6.0]
  def change
    create_table :repository_accesses, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :account_id, null: false
      t.bigint :github_id, null: false
      t.datetime :created_at,
                 null: false
      t.index %i(account_id),
              name: :index_account_id
    end
  end
end
