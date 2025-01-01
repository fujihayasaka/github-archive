# typed: true
class ChangeQueryPackUrlToBeNullableInCodeqlVariantAnalyses < ActiveRecord::Migration[7.1]
  def change
    change_column_null :codeql_variant_analyses, :query_pack_url, true
  end
end
