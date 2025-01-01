class SecretScanningResetValidity < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    create_table :secret_scanning_validation_resets, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :token_type, limit: 64, charset: "ascii", null: false, comment: "the token type this reset is for"
      t.string :tuple_token_types, limit: 512, charset: "ascii", null: true, comment: "if token_type is a root token type, then this column holds types the root is used with"
      t.datetime :reset_at, null: false, precision: 3, comment: "the time this reset was added. used to determine if standalone tokens and groups should be re-checked, and if continuation cursors should be reset"
      t.string :internal_reason, limit: 1024, null: false, comment: "internal (non customer facing) reason this reset was added"
      t.string :customer_facing_reason, limit: 1024, null: false, comment: "external reason this reset was added. shown to customers"

      t.index [:token_type, :reset_at], name: "index_token_type_reset_at", order: { reset_at: :desc }
    end
  end
end
