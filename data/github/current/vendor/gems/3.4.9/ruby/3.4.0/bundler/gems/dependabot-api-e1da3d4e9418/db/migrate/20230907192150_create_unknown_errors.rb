# frozen_string_literal: true

# rubocop:disable Rails/BulkChangeTable
class CreateUnknownErrors < ActiveRecord::Migration[7.0]
  def change
    create_table :unknown_errors do |t|
      t.bigint :update_job_id, null: false
      t.text :error_details, limit: 4_294_967_295
      t.string :error_type, limit: 40, null: false

      t.timestamps
    end

    add_index :unknown_errors, :update_job_id
    add_index :unknown_errors, %i(error_type created_at), name: "idx_uerr_ct_at"
  end
end
# rubocop:enable Rails/BulkChangeTable
