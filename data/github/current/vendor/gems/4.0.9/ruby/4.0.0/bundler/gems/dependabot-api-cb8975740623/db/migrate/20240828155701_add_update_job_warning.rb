# frozen_string_literal: true

class AddUpdateJobWarning < ActiveRecord::Migration[7.0]
  def change
    create_table :update_job_warnings, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.bigint :update_job_id, null: false
      t.string :warn_type, limit: 40, null: false
      t.string :warn_title, limit: 256, null: false
      t.text :warn_description, limit: 6500, null: true

      t.timestamps
    end

    add_index :update_job_warnings, :update_job_id
    add_index :update_job_warnings, %i(warn_type warn_title created_at), name: "idx_ujwarns_ct_at"
  end
end
