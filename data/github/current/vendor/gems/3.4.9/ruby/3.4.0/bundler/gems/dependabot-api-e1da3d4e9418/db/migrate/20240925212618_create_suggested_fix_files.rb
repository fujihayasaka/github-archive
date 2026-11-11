# frozen_string_literal: true

class CreateSuggestedFixFiles < ActiveRecord::Migration[7.0]
  def change
    create_table :suggested_fix_files, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.references :suggested_fix, unsigned: true, null: false
      t.string :file_path, null: false, limit: 4096
      t.binary :file_path_hash, null: false, limit: 32
      t.binary :file_checksum, null: false, limit: 20
      t.blob :diff_content, null: false
      t.timestamps
    end
  end
end
