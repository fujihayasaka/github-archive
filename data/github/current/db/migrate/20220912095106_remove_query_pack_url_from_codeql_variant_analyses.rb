# typed: true
class RemoveQueryPackUrlFromCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def change
    remove_column :codeql_variant_analyses, :query_pack_url, :text
  end
end
