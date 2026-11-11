# typed: true

class CreateSecretScanningValidationRootContinuations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    create_table :secret_scanning_validation_multipart_continuations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :root_token_scan_result_id, null: false, unsigned: true, comment: "the root token_scan_result id (e.g. id of a result for an AWS Access Key ID)"
      t.datetime :updated_at, null: false, precision: 6, comment: "when this record was updated"
      t.string :tuple_token_types, limit: 512, charset: "ascii", null: false, comment: "the comma delimited token types (asc alphabetically) which make up the the tuple for this continuation"
      t.datetime :last_processed_created_at, null: false, precision: 6, comment: "the last created at processed for this tuple group"
      t.string :last_processed_group_id, limit: 128, charset: "ascii", null: false, comment: "comma delimited list of ids that's used with last_processed_created_at to page through combinations. not necessarily a numerically ascending list of ids. the order depends on the order of tuple token types for a root."

      t.index [:root_token_scan_result_id, :tuple_token_types], name: "idx_root_token_scan_result_id_tuple_token_types", unique: true, comment: "natural key; allows continuations for token types A + B, and A + D + C to co-exist"
    end
  end
end
