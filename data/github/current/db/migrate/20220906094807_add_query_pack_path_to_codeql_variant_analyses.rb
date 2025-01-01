# typed: true

class AddQueryPackPathToCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def change
    add_column :codeql_variant_analyses, :query_pack_path, :string, null: true
  end
end
